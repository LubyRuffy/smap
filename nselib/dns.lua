

---
-- Table of DNS resource types
--
types = {
	A = 1,
	NS = 2,
	SOA = 6,
	CNAME = 5,
	PTR = 12,
	HINFO = 13,
	MX = 15,
	TXT = 16,
	AAAA = 28,
	SRV = 33,
	OPT = 41,
	SSHFP = 44,
	NSEC = 47,
	NSEC3 = 50,
	AXFR = 252,
	ANY = 255
}

CLASS = {
	IN = 1,
	CH = 3,
	ANY = 255
}

function newPacket()
	local pkt = {}
	pkt.id = 1
	pkt.flags = {}
	pkt.flags.RD = true
	pkt.questions = {}
	pkt.zones = {}
	pkt.updates = {}
	pkt.answers = {}
	pkt.auth = {}
	pkt.additional = {}
	return pkt
end


function addQuestion(ptk, dname, dtype, class)
	local class = class or CLASS.IN
	local q = {}
	q.dname = dname
	q.dtype = dtype
	q.class = class
	table.insert(pkt.querstions, q)
	return pkt
end

local function encodeflags(flags)
	local fb = 0

	if flags.QR then fb = fb|0x8000 end
	if flags.OC1 then fb = fb|0x4000 end
	if flags.OC2 then fb = fb|0x2000 end
	if flags.OC3 then fb = fb|0x1000 end
	if flags.OC4 then fb = fb|0x0800 end
	if flags.AA then fb = fb|0x0400 end
	if flags.TC then fb = fb|0x0200 end
	if flags.RD then fb = fb|0x0100 end
	if flags.RA then fb = fb|0x0080 end
	if flags.RC1 then fb = fb|0x0008 end
	if flags.RC2 then fb = fb|0x0004 end
	if flags.RC3 then fb = fb|0x0002 end
	if flags.RC4 then fb = fb|0x0001 end
	
	return fb

end


local function encodeAdditional(additional)
	if type(additional) ~= "table" then return nil end
end


local function encodeQuestions(questions)
	local encQ = {}

	for _, v in ipairs(questions) do
		encQ[#encQ + 1] = encodeFQDN(v.dname)
		encQ[#encQ + 1] = string.pack(">I2I2", v.dtype, v.class)
	end

	return table.concat(encQ)
end



function encode(pkt)
	local encFlags = encodeFlags(pkt.flags)
	local additional = encodeAdditional(pkt.additional)
	local aorplen = #pkt.answers
	local data, qorzlen, aorulen

	if(#pkt.questions > 0) then
		data = encodeQuestions(pkt.questions)
		qorzlen = #pkt.querstions
		aorulen = 0

	else
		print("is an update?")
	end

	local encStr

	encStr = string.pack(">I2I2I2I2I2I2", pkt.id, encFlags, qorzlen, aorplen, aorulen, #pkt.additional) .. data .. additional

	return encStr

end






function query(dname, options)
	if not options then options = {} end


	local dtype, host, port, proto = options.dtype, options.host, options.port, options.proto

	if proto == nil then proto = 'udp' end
	if port == nil then port = '53' end


	if not options.tries then options.tries = 10 end

	if not options.sendCount then options.sendCount = 2 end


	if type(dtype) == "string" then
		dtype = types[dtype]
	end

	if not dtype then dtype = types.A end


	local pkt = newPacket()

	addQuestion(pkt, dname, dtype, class)
	
	local data = encode(pkt)
























