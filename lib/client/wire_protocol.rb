require_relative '../utils/conversions'

module WireProtocol
  class Handshake1
    attr_reader :reserved, :info_hash
    def initialize(*a)
      @reserved, @info_hash = a
    end
    def to_s
      self.class.to_s + ": @info_hash=#{info_hash}"
    end
  end
  class Handshake2
    attr_reader :id
    def initialize(id)
      @id = id
    end
    def to_s
      self.class.to_s + ": @id=#{id}"
    end
  end

  class KeepAlive; end
  class Choke; end
  class Unchoke; end
  class Interested; end
  class NotInterested; end
  class Have
    attr_reader :index
    def initialize(index)
      @index = index
    end
  end
  class Bitfield
    attr_reader :bitfield
    def initialize(bitfield)
      @bitfield = bitfield
    end
  end
  class Request
    attr_reader :index, :start, :length
    def initialize(*a)
      @index, @start, @length = a
    end
    def to_s
      self.class.to_s + ": @index=#{index} @start=#{start} " +
        "@length=#{length}"
    end
  end
  class Piece
    attr_reader :index, :start, :block
    def initialize(*a)
      @index, @start, @block = a
    end
    def to_s
      self.class.to_s + ": @index=#{index} @start=#{start} " +
        "@length=#{block.length}"
    end
  end
  class Cancel
    attr_reader :index, :start, :length
    def initialize(*a)
      @index, @start, @length = a
    end
  end
  class Port
    attr_reader :port
    def initialize(port)
      @port = port
    end
  end

  class ProtocolException < Exception; end

  def WireProtocol.decode(data)
    return nil if data.length < 4
    length = data[0,4].unpack("N")[0]
    return KeepAlive.new if length == 0
    msg = data[4,length]
    return nil if msg.length < length
    case msg[0].unpack("C")[0]
    when 0
      assert_size(1, msg)
      Choke.new
    when 1
      assert_size(1, msg)
      Unchoke.new
    when 2
      assert_size(1, msg)
      Interested.new
    when 3
      assert_size(1, msg)
      NotInterested.new
    when 4
      assert_size(5, msg)
      Have.new(msg[1..-1].unpack("N")[0])
    when 5
      bitfield = msg[1..-1]
      Bitfield.new(bitfield)
    when 6
      assert_size(13, msg)
      index, start, length = msg[1..-1].unpack("NNN")
      Request.new(index, start, length)
    when 7
      # TODO: assert minimum size
      index, start = msg[1,8].unpack("NN")
      puts "msg size = " + msg.size.to_s
      puts "index = " + index.to_s
      puts "start = " + start.to_s
      block = msg[9..-1]
      puts "block = " + block.length.to_s
      Piece.new(index, start, block)
    when 8
      assert_size(13, msg)
      index, start, length = msg[1..-1].unpack("NNN")
      Cancel.new(index, start, length)
    when 9
      assert_size(3, msg)
      port = msg[1..-1].unpack("n")[0]
      Port.new(port)
    else
      puts "UNKNOWN MESSAGE"
      # TODO: warning
      nil
    end
  end

  def WireProtocol.decode_handshake_part1(data)
    if data.length >= 1 + 19 + 8 + 20
      header = [[19].pack('C'), "BitTorrent protocol"].join
      unless data.start_with?(header)
        fail ProtocolException, "not a bittorrent header"
      end
      reserved  = data[20,8].unpack("CCCCCCCC").join
      info_hash = Conversions.binary_id_to_hex(data[28,20])
      Handshake1.new(reserved, info_hash)
    end
  end

  def WireProtocol.decode_handshake_part2(data)
    if data.length >= 20
      Handshake2.new(Conversions.binary_id_to_hex(data[0,20]))
    end
  end

  def WireProtocol.encode(msg)
    case msg
    when Handshake1
      [[19].pack('C'), "BitTorrent protocol",
       msg.reserved,
       Conversions.hex_id_to_binary(msg.info_hash)].join
    when Handshake2
      Conversions.hex_id_to_binary(msg.id)
    when KeepAlive
      [0].pack("N")
    when Choke
      [1, 0].pack("NC")
    when Unchoke
      [1, 1].pack("NC")
    when Interested
      [1, 2].pack("NC")
    when NotInterested
      [1, 3].pack("NC")
    when Have
      [5, 4, msg.index].pack("NCN")
    when Bitfield
      b = [1 + msg.bitfield.length, 5].pack("NC") + msg.bitfield
      b
    when Request
      [13, 6, msg.index, msg.start, msg.length].pack("NCNNN")
    when Piece
      [9 + msg.block.length, 7, index, start].pack("NCNN") + msg.block
    when Cancel
      [13, 8, msg.index, msg.start, msg.length].pack("NCNNN")
    when Port
      [3, 9, msg.port].pack("NCn")
    end
  end

  def WireProtocol.size(msg)
    case msg
    when Handshake1    then 1 + 19 + 8 + 20
    when Handshake2    then 20
    when KeepAlive     then 4
    when Choke         then 5
    when Unchoke       then 5
    when Interested    then 5
    when NotInterested then 5
    when Have          then 9
    when Bitfield      then 5 + msg.bitfield.length
    when Request       then 17
    when Piece         then 13 + msg.block.length
    when Cancel        then 17
    when Port          then 7
    end
  end

  def WireProtocol.assert_size(size, msg)
    unless size == msg.length
      fail ProtocolException, "message size differs from expected"
    end
  end
end
