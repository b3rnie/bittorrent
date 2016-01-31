#!/usr/bin/ruby

require 'ipaddr'
require_relative 'types'
require_relative '../utils/conversions'

module ProtocolUdp
  def ProtocolUdp.encode(msg)
    case msg
    when ConnectQuery
      [msg.protocol_id >> 32,
       msg.protocol_id & 0xFFFFFFFF,
       0,
       msg.transaction_id].pack("NNNN")
    when ConnectReply
      [0,
       msg.transaction_id,
       msg.connection_id >> 32,
       msg.connection_id & 0xFFFFFFFF].pack("NNNN")
    when AnnounceQuery
      part1 = [msg.connection_id >> 32,
               msg.connection_id & 0xFFFFFFFF,
               1,
               msg.transaction_id].pack("NNNN")
      part2 = Conversions.hex_id_to_binary(msg.info_hash)
      part3 = Conversions.hex_id_to_binary(msg.peer_id)
      part4 = [(msg.downloaded >> 32) & 0xFFFFFFFF,
               msg.downloaded & 0xFFFFFFFF,
               (msg.left >> 32) & 0xFFFFFFFF,
               msg.left & 0xFFFFFFFF,
               (msg.uploaded >> 32) & 0xFFFFFFFF,
               msg.uploaded & 0xFFFFFFFF].pack("NNNNNN")
      part5 = [msg.event,
               msg.ip,
               msg.key,
               msg.num_want,
               msg.port].pack("NNNl>n")
      part1 + part2 + part3 + part4 + part5
    when AnnounceReply
      part1 = [1,
               msg.transaction_id,
               msg.interval,
               msg.leechers,
               msg.seeders].pack("NNNNN")
      part2 = msg.peers.map { |peer|
        [Conversions.string_ip_to_int(peer.ip), peer.port].pack("Nn")
      }.join
      part1 + part2
    when ScrapeQuery
      part1 = [msg.connection_id >> 32,
               msg.connection_id & 0xFFFFFFFF,
               2,
               msg.transaction_id].pack("NNNN")
      part2 = msg.info_hashes.map { |info_hash| Conversions.hex_id_to_binary(info_hash) }.join
      part1 + part2
    end
  end

  def ProtocolUdp.decode_server_query(data)
    return nil if data.length < 12
    connection_id = data[0,4].unpack("N")[0] << 32
    connection_id |= data[4,4].unpack("N")[0]
    action = data[8,4].unpack("N")[0]
    case action
    when 0
      return nil if data.length != 16
      transaction_id = data[12,4].unpack("N")[0]
      ConnectQuery.new(connection_id, transaction_id)
    when 1
      return nil if data.length != 98
      transaction_id = data[12, 4].unpack("N")[0]
      info_hash = Conversions.binary_id_to_hex(data[16,20])
      peer_id = Conversions.binary_id_to_hex(data[36,20])

      downloaded = data[56,4].unpack("N")[0] << 32
      downloaded |= data[60,4].unpack("N")[0]

      left = data[64,4].unpack("N")[0] << 32
      left |= data[68,4].unpack("N")[0]

      uploaded = data[72,4].unpack("N")[0] << 32
      uploaded |= data[76,4].unpack("N")[0]

      event = data[80,4].unpack("N")[0]

      ip = data[84,4].unpack("N")[0]

      key = data[88,4].unpack("N")[0]

      num_want = data[92,4].unpack("l>")[0]

      port = data[96,2].unpack("n")[0]

      AnnounceQuery.new(connection_id, transaction_id, info_hash, peer_id, downloaded,
                        left, uploaded, event, ip, key, num_want, port)
    when 2
      return nil if data.length < 36
      return nil if ((data.length - 16) % 20) != 0
      transaction_id = data[12, 4].unpack("N")[0]
      info_hashes = data[16..-1].chars.each_slice(20).map(&:join).map { |info_hash|
        info_hash
      }
      ScrapeQuery.new(connection_id, transaction_id, info_hashes)
    end
  end

  def ProtocolUdp.client_decode(data)
    return nil if data.length < 4
    case data[0,4].unpack("N")[0]
    when 0
      return nil if data.length != 16
      transaction_id = data[4,4].unpack("N")[0]
      connection_id  = data[8,4].unpack("N")[0] << 32
      connection_id |= data[12,4].unpack("N")[0]
      ConnectReply.new(transaction_id, connection_id)
    when 1
      return nil if data.length < 20
      return nil if ((data.length - 20) % 6) != 0
      transaction_id = data[4,4].unpack("N")[0]
      interval = data[8,4].unpack("N")[0]
      leechers = data[12,4].unpack("N")[0]
      seeders  = data[16,4].unpack("N")[0]
      peers    = data[20..-1].chars.each_slice(6).map(&:join).map { |s|
        [IPAddr.new(s[0,4].unpack("N")[0], Socket::AF_INET),
         s[4,2].unpack("n")[0]]
      }
      AnnounceReply.new(transaction_id, interval, leechers, seeders,
                        peers)
    when 2
      ScrapeReply.new
    when 3
      return nil if data.length < 8
      transaction_id = data[4,4].unpack("N")[0]
      message        = data[8,-1]
      ErrorReply.new(transaction_id, message)
    end
  end
end
