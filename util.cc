#include "util.h"

Ops o;

Ops::Ops():scripts(0),verbose(0)
{
	memset(device, 0, sizeof(device));

	strcpy(device, "wlp4s0");
}

Ops::~Ops()
{


}


void Ops::setScripts(char *arg)
{
	char *p, *next;

	while((p = strrchr(arg, ',')) != NULL){
		next = p + 1;
		
		scripts.push_back(std::string(next));
		
		std::cout << "saiyn : set script " << std::string(next) << std::endl; 

		*p = 0;
	}

	scripts.push_back(std::string(arg));


	std::cout << "saiyn : set script " << std::string(arg) << std::endl; 
}





