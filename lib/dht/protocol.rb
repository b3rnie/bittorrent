require "bencode"
require 'ipaddr'
require_relative 'types'
require_relative '../utils/conversions'

module Protocol
  def Protocol.encode_node_id(id)
    Conversions.hex_id_to_binary(id)
  end

  def Protocol.decode_node_id(id, tid)
    require_string(id, tid)
    begin
      fail if id.length != 20
      Conversions.binary_id_to_hex(id)
    rescue
      raise ProtocolException.new(tid), "invalid arguments"
    end
  end

  def Protocol.encode_ip(ip)
    [IPAddr.new(ip).to_i].pack("N")
  end

  def Protocol.decode_ip(ip, tid)
    begin
      ip = IPAddr.new(ip, Socket::AF_INET)
      ip.to_s
    rescue
      raise ProtocolException.new(tid), "invalid arguments"
    end
  end

  def Protocol.encode_port(port)
    [port].pack("n")
  end

  def Protocol.encode_implied_port(implied_port)
    implied_port ? 1 : 0
  end

  def Protocol.decode_implied_port(implied_port, tid)
    unless implied_port.nil?
      require_integer(implied_port, tid)
    end
    implied_port != 0
  end

  def Protocol.encode_values(values)
    values.map { |value|
      [encode_ip(value.ip), encode_port(value.port)].join
    }
  end

  def Protocol.decode_values(values, tid)
    begin
      values.map { |value|
        fail if value.size != 6
        [decode_ip(value[0,4].unpack("N").first, tid),
         require_port(value[4,2].unpack("n").first, tid)]
      }
    rescue
      raise ProtocolException.new(tid), "invalid arguments"
    end
  end

  def Protocol.encode_nodes(nodes)
    nodes.map { |id,ip,port|
      [encode_node_id(id),
       encode_ip(ip),
       encode_port(port)].join
    }.join
  end

  def Protocol.decode_nodes(nodes, tid)
    begin
      nodes_array = []
      while nodes.length != 0
        nodes_array << nodes.slice!(0, 26)
      end
      nodes_array.map { |node|
        fail if node.size != 26
        id   = decode_node_id(node[0,20], tid)
        ip   = decode_ip(node[20,4].unpack("N").first, tid)
        port = require_port(node[24,2].unpack("n").first, tid)
        [id, ip, port]
      }
    rescue
      raise ProtocolException.new(tid), "invalid arguments"
    end
  end

  def Protocol.decode(bin)
    begin
      msg = BEncode.load(bin)
      require_hash(msg, nil)
      tid = require_string(msg["t"], nil)
      case require_string(msg["y"], nil)
      when "q" then
        args = require_hash(msg["a"], tid)
        case msg["q"]
        when "ping" then
          PingQuery.new(tid, decode_node_id(args["id"], tid))
        when "find_node" then
          FindNodeQuery.new(tid,
                            decode_node_id(args["id"], tid),
                            decode_node_id(args["target"], tid))
        when "get_peers" then
          GetPeersQuery.new(tid,
                            decode_node_id(args["id"], tid),
                            decode_node_id(args["info_hash"], tid))
        when "announce_peer" then
          AnnouncePeerQuery.new(
            tid,
            decode_node_id(args["id"], tid),
            decode_implied_port(args["implied_port"], tid),
            decode_node_id(args["info_hash"], tid),
            require_port(args["port"], tid),
            require_string(args["token"], tid))
        else
          raise MethodUnknownException.new(tid), "method unknown"
        end
      when "r" then
        reply = require_hash(msg["r"], tid)
        Reply.new(
          tid    = tid,
          id     = decode_node_id(reply["id"], tid),
          token  = reply["token"],
          nodes  = reply["nodes"],
          values = reply["values"])
      when "e" then
        error = msg["e"]
        Error.new(tid, error[0], error[1])
      else
        raise MethodUnknownException.new(tid), "method unknown"
      end
    rescue BEncode::DecodeError
      raise ProtocolException.new(nil), "malformed packet"
    end
  end

  def Protocol.encode(msg)
    case msg
    when PingQuery
      ({"y" => "q",
        "t" => msg.tid,
        "q" => "ping",
        "a" => {"id" => encode_node_id(msg.id)}
       }).bencode
    when PingReply
      ({"y" => "r",
        "t" => msg.tid,
        "r" => {
          "id" => encode_node_id(msg.id)
        }
       }).bencode
    when FindNodeQuery
      ({"y" => "q",
        "t" => msg.tid,
        "q" => "find_node",
        "a" => {"id" => encode_node_id(msg.id),
                "target" => encode_node_id(msg.target)
               }
       }).bencode
    when FindNodeReply
      ({"y" => "r",
        "t" => msg.tid,
        "r" => {
          "id" => encode_node_id(msg.id),
          "nodes" => encode_nodes(msg.nodes)
        }
       }
      ).bencode
    when GetPeersQuery
      ({"y" => "q",
        "t" => msg.tid,
        "q" => "get_peers",
        "a" => { "id" => encode_node_id(msg.id),
                 "info_hash" => encode_node_id(msg.info_hash)
               }
       }).bencode
    when GetPeersReply
      ({"y" => "r",
        "t" => msg.tid,
        "r" => Hash.new.tap do |h|
          h["id"] = encode_node_id(msg.id)
          h["token"] = msg.token
          h["nodes"] = encode_nodes(msg.nodes) if !msg.nodes.empty?
          h["values"] = encode_values(msg.values) if !msg.values.empty?
        end
       }).bencode
    when AnnouncePeerQuery
      ({"y" => "q",
        "t" => msg.tid,
        "a" => {"id" => encode_node_id(msg.id),
                "implied_port" => encode_implied_port(msg.implied_port),
                "info_hash" => msg.info_hash,
                "port" => msg.port,
                "token" => msg.token
               }
       }).bencode
    when AnnouncePeerReply
      ({"y" => "r",
        "t" => msg.tid,
        "r" => {
          "id" => encode_node_id(msg.id)
        }
       }
      ).bencode
    when GenericException,
         ServerException,
         ProtocolException,
         MethodUnknownException
      (Hash.new.tap do |h|
        h["y"] = "e"
        h["t"] = msg.tid if msg.tid
        h["e"] = [exception_to_code(msg), msg.message]
       end).bencode
    end
  end

  def Protocol.build_reply(query, reply)
    case query
    when PingQuery
      PingReply.new(reply.tid, reply.id)
    when FindNodeQuery
      FindNodeReply.new(reply.tid,
                        reply.id,
                        decode_nodes(reply.nodes, reply.tid))
    when GetPeersQuery
      values = reply.values ? decode_values(reply.values, tid) : nil,
      nodes  = reply.nodes ? decode_nodes(reply.nodes, tid) : nil
      GetPeersReply.new(reply.tid,
                        reply.id,
                        require_string(reply.token, tid),
                        values,
                        nodes)
    when AnnouncePeerQuery
      AnnouncePeerReply.new(reply.tid, reply.id)
    end
  end

  def Protocol.exception_to_code(e)
    case e
    when GenericException then 201
    when ServerException then 202
    when ProtocolException then 203
    when MethodUnknownException then 204
    end
  end

  def Protocol.require_port(port, tid)
    begin
      fail if port < 1
      fail if port > 0xFFFF
      port
    rescue
      raise ProtocolException.new(tid), "invalid arguments"
    end
  end

  def Protocol.require_string(string, tid)
    require_type(string, tid, String)
  end

  def Protocol.require_hash(hash, tid)
    require_type(hash, tid, Hash)
  end

  def Protocol.require_integer(int, tid)
    require_type(int, tid, Fixnum)
  end

  def Protocol.require_type(o, tid, type)
    unless o.instance_of?(type)
      raise ProtocolException.new(tid), "invalid arguments"
    end
    o
  end
end
