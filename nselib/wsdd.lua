--local bin = require "bin"
local stdnse = require "stdnse"
local table = require "table"
_ENV = stdnse.module("wsdd", stdnse.seeall)

local HAVE_SSL, openssl = pcall(require,'openssl')

-- The different probes
local probes = {

  -- Detects devices supporting the WSDD protocol
  {
    name  = 'general',
    desc = 'Devices',
    data = '<env:Envelope xmlns:env="http://www.w3.org/2003/05/soap-envelope" ' ..
    'xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing" ' ..
    'xmlns:wsd="http://schemas.xmlsoap.org/ws/2005/04/discovery">' ..
    '<env:Header>' ..
    '<wsd:AppSequence InstanceId="1285624958737" MessageNumber="1" ' ..
    'SequenceId="urn:uuid:#uuid#"/>' ..
    '<wsa:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>' ..
    '<wsa:Action>' ..
    'http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe' ..
    '</wsa:Action><wsa:MessageID>urn:uuid:#uuid#</wsa:MessageID>' ..
    '</env:Header><env:Body><wsd:Probe/></env:Body></env:Envelope>'
  },

  -- Detects Windows Communication Framework (WCF) web services
  {
    name = 'wcf',
    desc = 'WCF Services',
    data = '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" ' ..
    'xmlns:a="http://www.w3.org/2005/08/addressing">' ..
    '<s:Header>' ..
    '<a:Action s:mustUnderstand="1">' ..
    'http://docs.oasis-open.org/ws-dd/ns/discovery/2009/01/Probe' ..
    '</a:Action>' ..
    '<a:MessageID>urn:uuid:#uuid#</a:MessageID>' ..
    '<a:To s:mustUnderstand="1">' ..
    'urn:docs-oasis-open-org:ws-dd:ns:discovery:2009:01' ..
    '</a:To>' ..
    '</s:Header>' ..
    '<s:Body>' ..
    '<Probe xmlns="http://docs.oasis-open.org/ws-dd/ns/discovery/2009/01">' ..
    '<Duration xmlns="http://schemas.microsoft.com/ws/2008/06/discovery">' ..
    'PT20S' ..
    '</Duration>' ..
    '</Probe>' ..
    '</s:Body>' ..
    '</s:Envelope>',
  }
}

-- A table that keeps track of received probe matches
local probe_matches = {}

Util = {

  --- Creates a UUID
  --
  -- @return uuid string containing a uuid
  generateUUID = function()
    --local rnd_bytes = select(2, bin.unpack( "H16", openssl.rand_bytes( 16 ) ) ):lower()

    --return ("%s-%s-%s-%s-%s"):format( rnd_bytes:sub(1, 8),
    --rnd_bytes:sub(9, 12), rnd_bytes:sub( 13, 16 ), rnd_bytes:sub( 17, 20 ),
    --rnd_bytes:sub(21, 32) )
    return "1234-56789-0123456-7890"
  end,

  --- Retrieves a probe from the probes table by name
  --
  -- @param name string containing the name of the probe to retrieve
  -- @return probe table containing the probe or nil if not found
  getProbeByName = function( name )
    for _, probe in ipairs(probes) do
      if ( probe.name == name ) then
        return probe
      end
    end
    return
  end,

  getProbes = function() return probes end,

  --sha1sum = function(data) return openssl.sha1(data) end

}

Decoders = {

  --- Decodes a wcf probe response
  --
  -- @param data string containing the response as received over the wire
  -- @return status true on success, false on failure
  -- @return response table containing the following fields
  --         <code>msgid</code>, <code>xaddrs</code>, <code>types</code>
  --         err string containing the error message
  ['wcf'] = function( data )
    local response = {}

    -- extracts the messagid, so we can check if we already got a response
    response.msgid = data:match("<[^:]*:MessageID>urn:uuid:([^<]*)</[^:]*:MessageID>")

    -- if unable to parse msgid return nil
    if ( not(response.msgid) ) then
      return false, "No message id was found"
    end

    response.xaddrs = data:match("<[^:]*:*XAddrs>(.*)</[^:]*:*XAddrs>")
    response.types = data:match("<[^:]*:Types>[wsdp:]*(.*)</[^:]*:Types>")

    return true, response
  end,

  --- Decodes a general probe response
  --
  -- @param data string containing the response as received over the wire
  -- @return status true on success, false on failure
  -- @return response table containing the following fields
  --         <code>msgid</code>, <code>xaddrs</code>, <code>types</code>
  --         err string containing the error message
  ['general'] = function( data )
    return Decoders['wcf'](data)
  end,

  --- Decodes an error message received from the service
  --
  -- @param data string containing the response as received over the wire
  -- @return status true on success, false on failure
  -- @return err string containing the error message
  ['error'] = function( data )
    local err = data:match("<SOAP.-ENV:Reason><SOAP.-ENV:Text>(.-)<")
    local response = "Failed to decode response from device: "
    .. (err or "Unknown error")

    return true, response
  end,

}


Comm = {

  --- Creates a new Comm instance
  --
  -- @param host string containing the host name or ip
  -- @param port number containing the port to connect to
  -- @return o a new instance of Comm
  new = function( self, host, port, mcast )
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.host = host
    o.port = port
    o.mcast = mcast or false
    o.sendcount = 2
    o.timeout = 5000
    return o
  end,

  --- Sets the timeout for socket reads
  setTimeout = function( self, timeout ) self.timeout = timeout end,

  --- Sends a probe over the wire
  --
  -- @return status true on success, false on failure
  sendProbe = function( self )
    local status, err

    -- replace all instances of #uuid# in the probe
    local probedata = self.probe.data:gsub("#uuid#", Util.generateUUID())

    if ( self.mcast ) then
      self.socket = nsock.new("udp")
      self.socket:set_timeout(self.timeout)
    --else
      --self.socket = nmap.new_socket()
      --self.socket:set_timeout(self.timeout)
      --status, err = self.socket:connect( self.host, self.port, "udp" )
      --if ( not(status) ) then return err end
    end

    for i=1, self.sendcount do
      if ( self.mcast ) then
        status, err = self.socket:sendto( self.host, self.port, probedata )
      else
        status, err = self.socket:send( probedata )
      end
      if ( not(status) ) then return err end
    end
    return true
  end,

  --- Sets a probe from the <code>probes</code> table to send
  --
  -- @param probe table containing a probe from <code>probes</code>
  setProbe = function( self, probe )
    self.probe = probe
  end,

  --- Receives one or more responses for a Probe
  --
  -- @return table containing decoded responses suitable for
  --         <code>stdnse.format_output</code>
  recvProbeMatches = function( self )
    local responses = {}
    repeat
      local data

      local status, data = self.socket:receive()
      if ( not(status) ) then
        if ( data == "TIMEOUT" ) then
          break
        else
          return false, data
        end
      end

      --local _, ip
      --status, _, _, ip, _ = self.socket:get_info()
      --if( not(status) ) then
        --return false, "ERROR: Failed to get socket info"
      --end

      -- push the unparsed response to the response table
      local status, response = Decoders[self.probe.name]( data )
      local id, output
      -- if we failed to decode the response indicate this
      if ( status ) then
        output = {}
        table.insert(output, "Message id: " .. response.msgid)
        if ( response.xaddrs ) then
          table.insert(output, "Address: " .. response.xaddrs)
        end
        if ( response.types ) then
          table.insert(output, "Type: " .. response.types)
        end
        id = response.msgid
      else
        status, response = Decoders["error"](data)
        output = response
        id = Util.sha1sum(data)
      end

      if ( self.mcast and not(probe_matches[id]) ) then
        responses = output
      end

      -- avoid duplicates
      probe_matches[id] = true
    until( not(self.mcast) )

    -- we're done with the socket
    self.socket:close()

    return true, responses
  end

}

Helper = {

  --- Creates a new helper instance
  --
  -- @param host string containing the host name or ip
  -- @param port number containing the port to connect to
  -- @return o a new instance of Helper
  new = function( self, host, port )
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.host = host
    o.port = port
    o.mcast = true
    o.timeout = 5000
    return o
  end,

  --- Instructs the helper to use unconnected sockets supporting multicast
  --
  -- @param mcast boolean true if multicast is to be used, false otherwise
  setMulticast = function( self, mcast )
    assert( type(mcast)=="boolean", "mcast has to be either true or false")
    local family = "inet"
    self.mcast = mcast
    self.host = (family=="inet6" and "FF02::C" or "239.255.255.250")
    self.port = 3702
  end,

  --- Sets the timeout for socket reads
  setTimeout = function( self, timeout ) self.timeout = timeout end,

  --- Sends a probe, receives and decodes a probematch
  --
  -- @param probename string containing the name of the probe to send
  --        check <code>probes</code> for available probes
  -- @return status true on success, false on failure
  -- @return matches table containing responses, suitable for printing using
  --         the <code>stdnse.format_output</code> function
  discoverServices = function( self, probename )
    --if ( not(HAVE_SSL) ) then return false, "The wsdd library requires OpenSSL" end

    local comm = Comm:new(self.host, self.port, self.mcast)
    local probe = Util.getProbeByName(probename)
    comm:setProbe( probe )
    comm:setTimeout( self.timeout )

    local status = comm:sendProbe()
    if ( not(status) ) then
      return false, "ERROR: wcf.discoverServices failed"
    end

    local status, matches = comm:recvProbeMatches()
    if ( not(status) ) then
      return false, "ERROR: wcf.recvProbeMatches failed"
    end

    if ( #matches > 0 ) then matches.name = probe.desc end
    return true, matches
  end,

  --- Sends a general probe to attempt to discover WSDD supporting devices
  --
  -- @return status true on success, false on failure
  -- @return matches table containing responses, suitable for printing using
  --         the <code>stdnse.format_output</code> function
  discoverDevices = function( self )
    return self:discoverServices('general')
  end,


  --- Sends a probe that attempts to discover WCF web services
  --
  -- @return status true on success, false on failure
  -- @return matches table containing responses, suitable for printing using
  --         the <code>stdnse.format_output</code> function
  discoverWCFServices = function( self )
    return self:discoverServices('wcf')
  end,

}

return _ENV;
