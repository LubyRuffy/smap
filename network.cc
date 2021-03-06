#include <unistd.h>
#include <sys/types.h>

#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/if_packet.h>
#include <netinet/if_ether.h>
#include <sys/time.h>
#include <net/route.h>
#include <sys/ioctl.h>


#include "network.h"



NetworkInfoHelper& NetworkInfoHelper::GetInstance()
{
	static NetworkInfoHelper instance;

	return instance;
}


NetworkInfoHelper::NetworkInfoHelper()
{
	getAdapterInfo();

	m_cur_if.print();
}



#define BUF_SIZE  (8192)

int NetworkInfoHelper::readNlSock(int sock, char *msg, int seq, int pid)
{
	struct nlmsghdr *nlHdr = NULL;
	int readLen =0, msgLen = 0;

	do{
		if((readLen = recv(sock, msg, BUF_SIZE - msgLen, 0)) < 0) return -1;

		nlHdr = (struct nlmsghdr *)msg;
		
		if((NLMSG_OK(nlHdr, readLen) == 0) || (nlHdr->nlmsg_type == NLMSG_ERROR)) return -1;

		if(nlHdr->nlmsg_type == NLMSG_DONE)
		{
			break;
		}
		else
		{
			msg += readLen;
			msgLen += readLen;
		}

		/* check if it's a multi part message */

		if((nlHdr->nlmsg_flags & NLM_F_MULTI) == 0)
		{
			break;
		}
	

	}while((nlHdr->nlmsg_seq != seq) || (nlHdr->nlmsg_pid != pid));


	return msgLen;
}


int NetworkInfoHelper::parseOneRoute(struct nlmsghdr *nlHdr, RouteInfo *rtinfo)
{
	struct rtmsg *rtMsg = NULL;
	struct rtattr *rtAttr = NULL;
	int rtLen = 0;

	rtMsg = (struct rtmsg *)NLMSG_DATA(nlHdr);
	if((rtMsg->rtm_family != AF_INET) || (rtMsg->rtm_table != RT_TABLE_MAIN)) return 0;

	rtAttr = (struct rtattr *)RTM_RTA(rtMsg);
	rtLen = RTM_PAYLOAD(nlHdr);

	for(;RTA_OK(rtAttr, rtLen); rtAttr = RTA_NEXT(rtAttr, rtLen))
	{
		switch(rtAttr->rta_type)
		{
			case RTA_OIF:
				rtinfo->index = *(int *)RTA_DATA(rtAttr);
			break;

			case RTA_GATEWAY:
				rtinfo->gateway = *(unsigned int *)RTA_DATA(rtAttr);
			break;

			case RTA_PREFSRC:
				rtinfo->src_ipv4 = *(unsigned int *)RTA_DATA(rtAttr);
			break;

			case RTA_DST:
				rtinfo->dst_ipv4 = *(unsigned int *)RTA_DATA(rtAttr);
			break;

			case RTA_PRIORITY:
				rtinfo->metric = *(unsigned int *)RTA_DATA(rtAttr);
			break;

			default:
				std::cout << "miss support for: " << rtAttr->rta_type << "  in " << __FUNCTION__ << std::endl;
			break;

		}
	}


	return 1;
}


NetworkInfoHelper::RouteInfo* NetworkInfoHelper::GetAllRouteInfo()
{

	struct nlmsghdr *nlMsg = NULL;
	struct rtmsg *rtMsg = NULL;
	int sock,len,msgSeq = 0;
	char msgBuf[BUF_SIZE];

	if((sock = socket(PF_NETLINK, SOCK_DGRAM, NETLINK_ROUTE)) < 0)
	{
		std::cout << "create socket fail in func: " << __FUNCTION__ << std::endl;
		return NULL;
	}

	nlMsg = (struct nlmsghdr *)msgBuf;
	rtMsg = (struct rtmsg *)NLMSG_DATA(nlMsg);
	nlMsg->nlmsg_len = NLMSG_LENGTH(sizeof(struct rtmsg));
	nlMsg->nlmsg_type = RTM_GETROUTE;
	nlMsg->nlmsg_flags = NLM_F_DUMP | NLM_F_REQUEST;
	nlMsg->nlmsg_seq = msgSeq++;
	nlMsg->nlmsg_pid = getpid();


	RouteInfo *rtinfo, *head = NULL;

	do
	{

		if(send(sock, nlMsg, nlMsg->nlmsg_len, 0) < 0)
		{
			std::cout << "send fail in func: " << __FUNCTION__ << std::endl;
			break;
		}	
	
		if((len = readNlSock(sock, msgBuf, msgSeq, getpid())) <= 0)
		{
			break;
		}

		for(;NLMSG_OK(nlMsg, len); nlMsg = NLMSG_NEXT(nlMsg, len))
		{
			rtinfo = new (std::nothrow)RouteInfo;

			if(parseOneRoute(nlMsg, rtinfo))
			{
				//std::cout << "link one route: " << std::endl; 

				//rtinfo->print(); 

				list_link(rtinfo, &head);
			}
			else
			{
				delete rtinfo;
			}		
		}
	}while(0);

	close(sock);

	return head;
}



int NetworkInfoHelper::GetDefaultGateway(unsigned int &ip, unsigned int &eth_index)
{
	int ret = 0;


	RouteInfo *info = GetAllRouteInfo();

	for(RouteInfo *entry = info; entry; entry = entry->next)
	{
		if(entry->dst_ipv4 == 0x0)
		{
			eth_index = entry->index;
			ip = entry->gateway;
			ret = 1;
		}

	}

	free_list(info);

	return ret;
}


void NetworkInfoHelper::getAdapterInfo()
{
	int fd, interface;

	struct ifreq buf[40] = {{0}};
	struct ifconf ifc;

	unsigned int gateway_ip, gateway_index;

	if(!GetDefaultGateway(gateway_ip, gateway_index))
	{
		return;
	}

	
	if((fd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) return;

	ifc.ifc_len = sizeof(buf);
	ifc.ifc_buf = (caddr_t)buf;

	if(ioctl(fd, SIOCGIFCONF, (char *)&ifc))
	{
		close(fd);
		return;
	}

	interface = ifc.ifc_len / sizeof(ifreq);

	if(interface == 0) return;

	while(interface--)
	{
		if(ioctl(fd, SIOCGIFFLAGS, (char *)&buf[interface])) continue;

		if(!(buf[interface].ifr_flags & IFF_UP)) continue;

		if(ioctl(fd, SIOCGIFINDEX, (char *)&buf[interface])) continue;

		//get index and name
		if(buf[interface].ifr_ifindex != gateway_index) continue;

		m_cur_if.adaptor.index = buf[interface].ifr_ifindex;
		m_cur_if.adaptor.adapter_name = buf[interface].ifr_name;
		
		//get local ip
		if(!ioctl(fd, SIOCGIFADDR, (char *)&buf[interface]))
		{
			m_cur_if.adaptor.local_ipv4 = ((struct sockaddr_in *)(&buf[interface].ifr_addr))->sin_addr;
		}

		//get local mac
		if(!ioctl(fd, SIOCGIFHWADDR, (char *)&buf[interface]))
		{
			memcpy(m_cur_if.adaptor.local_mac, buf[interface].ifr_hwaddr.sa_data, 6);
		}

		//get net mask
		if(!ioctl(fd, SIOCGIFNETMASK, (char *)&buf[interface]))
		{
			m_cur_if.adaptor.mask_ipv4 = ((struct sockaddr_in *)(&buf[interface].ifr_netmask))->sin_addr;
		}

		//get gateway info
		m_cur_if.adaptor.gateway_ipv4.s_addr = gateway_ip;
		
		getMac(gateway_ip, &m_cur_if.adaptor, m_cur_if.adaptor.gateway_mac,1000);

		break;
	}

	close(fd);
}

static int arp_send_recv(int sock, char packet[], size_t sz, int index, unsigned int dst_ip,unsigned char mac[], unsigned int tt)
{
	struct sockaddr_ll saddr_ll = {0};

	saddr_ll.sll_ifindex = index;
	saddr_ll.sll_family = AF_PACKET;

	unsigned char recv_buf[1024] = {0};
	struct timeval t;

	gettimeofday(&t, NULL);

	unsigned long long start = t.tv_sec * 1000000 + t.tv_usec;

	for(;;)
	{
		
		if(sendto(sock, packet, sz, 0,(struct sockaddr *)&saddr_ll, sizeof(saddr_ll)) < 0)
		{
			std::cout << "sendto fail at: " << __FUNCTION__ << std::endl;

			close(sock);
			return -1;
		}

		ssize_t recv_sz = recv(sock, recv_buf, sizeof(recv_buf), 0);
		if(recv_sz >= sz)
		{
			struct ether_arp *arp = (struct ether_arp *)(recv_buf + sizeof(struct ether_header));
			
			if(*(unsigned int *)(arp->arp_spa) == dst_ip)
			{
				memcpy(mac, arp->arp_sha, ETH_ALEN);

				break;
			}
			else
			{
				std::cout << "discard arp resp from: " << inet_ntoa(*(struct in_addr *)(arp->arp_spa)) << std::endl;
			}
		}

		gettimeofday(&t, NULL);
		unsigned long long current = t.tv_sec * 1000000 + t.tv_usec;
		if((current - start) > tt*1000)
		{

			std::cout << "recive arp rsp timeout: " << __LINE__ << std::endl;

			close(sock);
			return -1;
		}

	}


	close(sock);
	return 0;
}

int NetworkInfoHelper::getMac(unsigned int dst_ip, AdapteInfo *info, unsigned char mac[],unsigned int timeout)
{
	if(dst_ip == 0) return -1;

	if(info->local_ipv4.s_addr == 0) return -1;

	int sock = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ARP));
	if(sock < 0) return -1;

	struct timeval recv_tt = {0};
	recv_tt.tv_usec = 100*1000;
	if(setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (const char *)&recv_tt, sizeof(recv_tt)))
	{
		close(sock);
		return -1;
	}

	struct timeval send_tt = {0};
	send_tt.tv_usec = 100*1000;
	if(setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (const char *)&send_tt, sizeof(send_tt)))
	{
		close(sock);
		return -1;
	}

	char packet[sizeof(struct ether_header) + sizeof(struct ether_arp)] = {0};
		
	struct ether_header *ethHdr = (struct ether_header *)packet;
	struct ether_arp *arp = (struct ether_arp *)(packet + sizeof(*ethHdr));

	memset(ethHdr->ether_dhost, 0xff, ETH_ALEN);
	memcpy(ethHdr->ether_shost, info->local_mac, ETH_ALEN);
	ethHdr->ether_type = htons(ETHERTYPE_ARP);

	memcpy(arp->arp_sha, ethHdr->ether_shost, ETH_ALEN);
	arp->arp_hrd = htons(ARPHRD_ETHER);
	arp->arp_pro = htons(ETHERTYPE_IP);
	arp->arp_hln = ETH_ALEN;
	arp->arp_pln = 4;
	arp->arp_op = htons(ARPOP_REQUEST);
	*(unsigned int *)(arp->arp_spa) = info->local_ipv4.s_addr;
	*(unsigned int *)(arp->arp_tpa) = dst_ip;
	
	return arp_send_recv(sock, packet, sizeof(packet),info->index , dst_ip ,mac, timeout);
}



















