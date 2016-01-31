require 'set'
require_relative 'rate'
require_relative 'socket_buffer'
require_relative 'wire_protocol'

class PeerException < Exception; end

class Peer
  KEEPALIVE_INTERVAL           = 120

  TYPE_INCOMING                = 0
  TYPE_OUTGOING                = 1

  STATE_WAITING_FOR_HANDSHAKE1 = 0
  STATE_WAITING_FOR_HANDSHAKE2 = 1
  STATE_OK                     = 2
  STATE_ERROR                  = 3

  attr_reader :state
  attr_reader :id
  attr_reader :ip, :port

  attr_reader :peer_interested, :peer_choked
  attr_reader :rate
  attr_reader :self_requested

  def initialize(options = {})
    @logger             = options[:logger]
    @my_node_id         = options[:my_node_id]
    @my_reserved        = options[:my_reserved]
    @torrent            = options[:torrent]
    @torrents           = options[:torrents]
    @type               = options[:type]

    # connection state
    @self_interested    = false
    @peer_interested    = false
    @self_choked        = true
    @peer_choked        = true

    @self_last_keepalive= Time.now.to_i
    @peer_last_keepalive= nil
    @self_message_count = 0
    @peer_message_count = 0
    @bitfield           = nil
    @reserved           = nil
    @rate               = Rate.new

    # block
    @self_requested     = Set.new
    @peer_requested     = Set.new

    @state              = STATE_WAITING_FOR_HANDSHAKE1

    @socket_buffer      = SocketBuffer.new(:logger => @logger,
                                           :rate   => @rate,
                                           :socket => options[:socket])

    write_handshake if @type == TYPE_OUTGOING
  end

  def update
    begin
      read_handshake_part1 if @state == STATE_WAITING_FOR_HANDSHAKE1
      read_handshake_part2 if @state == STATE_WAITING_FOR_HANDSHAKE2
      read_messages        if @state == STATE_OK
      request_blocks       if @state == STATE_OK
      write_blocks         if @state == STATE_OK
      write_keepalive      if @state == STATE_OK
      update_interest      if @state == STATE_OK
    rescue WireProtocol::ProtocolException,
      PeerException,
      BitfieldException => e
      puts "ERROR"
      puts e
      @logger.error(e.backtrace)
      puts e.backtrace
      @socket_buffer.close
      @state = STATE_ERROR
    end
  end

  def stop?
    !@socket_buffer.is_open? || @state == STATE_ERROR
  end

  def stop
    @socket_buffer.close
  end

  def info_hash; @torrent.info_hash end

  # socket buffer
  def ready_to_read?;  @socket_buffer.ready_to_read? end
  def ready_to_write?; @socket_buffer.ready_to_write? end
  def try_read;        @socket_buffer.try_read end
  def try_write;       @socket_buffer.try_write end
  def socket;          @socket_buffer.socket end

  # controls
  def choke
    @peer_choked = true
    @peer_requested.clear
    write(WireProtocol::Choke.new)
  end

  def unchoke
    @peer_choked = false
    write(WireProtocol::Unchoke.new)
  end

  def have(piece)
    write(WireProtocol::Have.new(piece))
  end

  def cancel(block)
    if @self_requested.include?(block)
      write(WireProtocol::Cancel.new(block.piece,
                                     block.start,
                                     block.length))
      @self_requested.delete(block)
    end
  end

  # misc
  def ==(o)
    o.instance_of?(self.class) && @id == o.id
  end

  def eql?(o)
    self == o
  end

  private
  # handshake related
  def write_handshake
    write(WireProtocol::Handshake1.new(@my_reserved,
                                       @torrent.info_hash))
    write(WireProtocol::Handshake2.new(@my_node_id))
  end

  def write_bitfield
    unless @torrent.bitfield.no_piece_set?
      bytestring = @torrent.bitfield.to_bytestring
      write(WireProtocol::Bitfield.new(bytestring))
    end
  end

  def read_handshake_part1
    if msg = WireProtocol.decode_handshake_part1(@socket_buffer.in)
      @socket_buffer.advance(WireProtocol.size(msg))
      @reserved  = msg.reserved
      @state     = STATE_WAITING_FOR_HANDSHAKE2
      case @type
      when TYPE_INCOMING
        @torrent = find_torrent(msg.info_hash)
        write_handshake
      when TYPE_OUTGOING
        if msg.info_hash != @torrent.info_hash
          fail PeerException, "wrong info_hash in handshake"
        end
      end
    end
  end

  def read_handshake_part2
    if msg = WireProtocol.decode_handshake_part2(@socket_buffer.in)
      @socket_buffer.advance(WireProtocol.size(msg))
      @id       = msg.id
      @state    = STATE_OK
      @bitfield = Bitfield.new(@torrent.bitfield.size)
      write_bitfield
    end
  end

  # handling incoming messages
  def read_messages
    loop do
      msg = read()
      break if msg.nil?
      handle_message(msg)
    end
  end

  def handle_message(msg)
    # @logger.info("in.length  = " + @socket_buffer.in.length.to_s)
    # @logger.info("out.length = " + @socket_buffer.out.length.to_s)
    case msg
    when WireProtocol::KeepAlive
      @peer_last_keepalive = Time.now.to_i
    when WireProtocol::Choke
      handle_message_choke
    when WireProtocol::Unchoke
      @self_choked = false
    when WireProtocol::Interested
      @peer_interested = true
    when WireProtocol::NotInterested
      @peer_interested = false
    when WireProtocol::Have
      @bitfield.set(msg.index)
    when WireProtocol::Bitfield
      handle_message_bitfield(msg)
    when WireProtocol::Request
      handle_message_request(msg)
    when WireProtocol::Piece
      handle_message_piece(msg)
    when WireProtocol::Cancel
      handle_message_cancel(msg)
    when WireProtocol::Port
      # TODO: DHT routing table related
    end
  end

  def handle_message_choke
    @torrent.return_blocks(@self_requested)
    @self_choked = true
    @self_requested.clear
  end

  def handle_message_bitfield(msg)
    if @peer_message_count != 1
      raise PeerException, "bitfield is out of order"
    end
    @bitfield.from_bytestring(msg.bitfield)
  end

  def handle_message_request(msg)
    unless @torrent.bitfield.is_set?(msg.index)
      fail PeerException, "peer requested a piece we dont have"
    end
    unless @peer_interested
      fail PeerException, "peer is not interested but requested a piece"
    end
    unless @peer_choked == false
      # TODO: check if it's a valid block
      block = Block.new(msg.index, msg.start, msg.length)
      @peer_requested.add(block)
    end
  end

  def handle_message_piece(msg)
    # TODO: check if valid block
    block = Block.new(msg.index, msg.start, msg.block.length)
    @self_requested.delete(block)
    @torrent.block_done(block, msg.block)
  end

  def handle_message_cancel(msg)
    # TODO: check if valid
    block = Block.new(msg.index, msg.start, msg.length)
    @peer_requested.delete(block)
  end

  # pieces/block related
  def request_blocks
    if @self_interested && !@self_choked
      blocks = @torrent.request_blocks(@self_requested.size,
                                       @bitfield)
      blocks.each { |block|
        unless @self_requested.include?(block)
          @self_requested.add(block)
          write(WireProtocol::Request.new(block.piece,
                                          block.start,
                                          block.length))
        end
      }
    end
  end

  def write_blocks
    @peer_requested.each { |block|
      fail "peer is choked" if @peer_choked == true
      fail "peer not interested" if @peer_interested == false
      break if @socket_buffer.out_full?
      data = @torrent.io.read(block.index, block.start, block.length)
      write(WireProtocol::Piece.new(block.index, block.start, data))
    }
  end

  # keepalive
  def write_keepalive
    now = Time.now.to_i
    if @self_last_keepalive + KEEPALIVE_INTERVAL < now
      @self_last_keepalive = now
      write(WireProtocol::KeepAlive.new)
    end
  end

  # interest related
  def update_interest
    case [@torrent.peer_interesting?(@bitfield),
          @self_requested.empty?]
    when [true, true] then ensure_interested
    when [true, false]
      fail "requested pieces but not interested" unless @self_interested
    when [false, true] then ensure_not_interested
    when [false, false]
      fail "requested pieces but not interested" unless @self_interested
    end
  end

  def ensure_interested
    unless @self_interested
      @self_interested = true
      write(WireProtocol::Interested.new)
    end
  end

  def ensure_not_interested
    if @self_interested
      @self_interested = false
      write(WireProtocol::NotInterested.new)
    end
  end

  # misc helpers
  def find_torrent(info_hash)
    @torrents.find(-> { fail PeerException, "unknown torrent" }) {
      |torrent| torrent.info_hash == info_hash
    }
  end

  def read()
    if msg = WireProtocol.decode(@socket_buffer.in)
      @logger.debug("in = " + msg.to_s)
      @socket_buffer.advance(WireProtocol.size(msg))
      @peer_message_count += 1
      msg
    end
  end

  def write(msg)
    @logger.debug("out = " + msg.to_s)
    @socket_buffer.concat(WireProtocol.encode(msg))
  end
end
