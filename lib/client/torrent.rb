require 'set'
require 'socket'
require 'uri'
require 'digest/sha1'
require_relative 'bitfield'
require_relative 'stats'
require_relative 'torrent_io'

class Torrent
  MAX_PEERS                           = 32
  PENDING_BLOCK_THRESHOLD_DOWNLOADING = 20
  PENDING_BLOCK_THRESHOLD_ENDGAME     = 4

  STATE_DOWNLOADING                   = 0
  STATE_ENDGAME                       = 1 # all blocks requested
  STATE_DONE                          = 2

  attr_reader :peers
  attr_reader :bitfield

  def initialize(options = {})
    @logger                = options[:logger]
    @metainfo_file         = options[:metainfo_file]
    @my_node_id            = options[:my_node_id]
    @output_path           = options[:output_path]
    @tracker               = options[:tracker]
    @peers                 = []
    @blocks_left           = nil
    @blocks_requested      = nil
    @choke_last            = 0
    @choke_optimistic_last = 0
    @choke_optimistic_peer = nil

    @metainfo              = Metainfo.new(:file => @metainfo_file)
    @bitfield              = Bitfield.new(@metainfo.pieces.length)
    @stats                 = Stats.new(123456) # FIXME
    @io                    = TorrentIO.new(:logger   => @logger,
                                           :metainfo => @metainfo,
                                           :path     => @output_path)
    check_existing_pieces
    start_announce
  end

  def update
    @peers.reject! { |peer|
      if peer.stop?
        return_blocks(peer.self_requested)
        true
      end
    }
    @peers.each { |peer|
      peer.update }
    connect_to_peers
    run_choke_algorithm
  end

  def info_hash
    @metainfo.info_hash
  end

  def stop
    @peers.each { |peer| peer.stop }
    @tracker.stop_announce(@metainfo.info_hash)
    @io.stop
  end

  def request_blocks(pending, bitfield)
    if @state == STATE_DOWNLOADING
      if @blocks_left.all? { |set| set.empty? }
        @logger.debug("endgame state")
        @state = STATE_ENDGAME
      end
    end

    case @state
    when STATE_DONE
      []
    when STATE_DOWNLOADING
      # TODO: 'rarest first'
      count  = PENDING_BLOCK_THRESHOLD_DOWNLOADING - pending
      blocks = []
      (bitfield - @bitfield).existing_pieces.each { |piece|
        return blocks if count <= 0
        unless @blocks_left[piece].empty?
          t = @blocks_left[piece].take(count)
          blocks                   += t
          count                    -= t.size
          @blocks_requested[piece] += t
          @blocks_left[piece]      -= t
        end
      }
      blocks
    when STATE_ENDGAME
      count  = PENDING_BLOCK_THRESHOLD_ENDGAME - pending
      blocks = []
      (bitfield - @bitfield).existing_pieces.shuffle.each { |piece|
        return blocks if count <= 0
        t = @blocks_requested[piece].take(count)
        blocks += t
        count  -= t.size
      }
      blocks
    end
  end

  def return_blocks(blocks)
    if @state == STATE_DOWNLOADING
      blocks.each { |block|
        @blocks_left[block.piece].add(block)
        @blocks_requested[block.piece].delete(block)
      }
    end
  end

  def block_done(block, data)
    if @state == STATE_ENDGAME
      if @blocks_requested[block.piece].include?(block)
        @peers.each { |peer| peer.cancel(block) }
      end
    end

    if @blocks_left[block.piece].include?(block) ||
        @blocks_requested[block.piece].include?(block)
      @blocks_left[block.piece].delete(block)
      @blocks_requested[block.piece].delete(block)
      @io.write(block.piece, block.start, data)
      if @blocks_left[block.piece].empty? &&
          @blocks_requested[block.piece].empty?
        @logger.debug("all blocks done for piece #{block.piece}")
        # TODO: better check - warning if it doesn't pass
        # handle corrupt pieces
        @io.check_piece(block.piece) {
          @logger.debug("piece #{block.piece} done")
          @bitfield.set(block.piece)
          @peers.each { |peer| peer.have(block.piece) }
        }
        if @blocks_left.all? { |piece|
            piece.empty?
          } && @blocks_requested.all? { |piece|
            piece.empty?
          }
          # TODO: handle situation when pieces are corrupt
          @state = STATE_DONE
        end
      end
    end
  end

  def peer_interesting?(bitfield)
    requestable = bitfield - @bitfield
    case @state
    when STATE_DONE then false
    when STATE_DOWNLOADING
      requestable.existing_pieces.any? { |piece|
        !@blocks_left[piece].empty?
      }
    when STATE_ENDGAME
      requestable.existing_pieces.any? { |piece|
        !@blocks_requested[piece].empty?
      }
    end
  end

  private
  # file related
  def check_existing_pieces
    @io.check_all_pieces { |piece|
      @bitfield.set(piece)
    }
    case @bitfield.all_pieces_set?
    when true
      @logger.info("torrent done")
      @state = STATE_DONE
    when false
      @logger.info("torrent incomplete")
      length            = @metainfo.pieces.length
      @state            = STATE_DOWNLOADING
      @blocks_left      = Array.new(length) { Set.new }
      @blocks_requested = Array.new(length) { Set.new }
      @bitfield.missing_pieces.each { |piece|
        puts "missing #{piece}"
        @blocks_left[piece] += @io.blocks(piece)
      }
    end
  end

  # tracker related
  def start_announce
    # TODO: reflect status
    @tracker.start_announce(@metainfo.info_hash,
                            @stats,
                            @metainfo.announce)
  end

  # choking
  def run_choke_algorithm
    now = Time.now.to_i
    if @choke_optimistic_last + 30 < now
      run_optimistic_choke_algorithm
      @choke_optimistic_last = now
    end
    if @choke_last + 10 < now
      run_normal_choke_algorithm
      @choke_last = now
    end
  end

  def run_optimistic_choke_algorithm
    # optimistic unchoking
    # rotates every 30 seconds

    # TODO: make newly connected peers 3 times as likely to
    # be sampled
    if @choke_optimistic_peer = @peers.sample
      if @choke_optimistic_peer.peer_choked
        @choke_optimistic_peer.unchoke_peer
      end
      run_normal_choke_algorithm
      @choke_last = Time.now.to_i
    end
  end

  def run_choke_algorithm
    # run once every 10 seconds
    # unchoke the 4 peers which has the best upload rate
    # and are interested

    # peers that has better upload rate but arent interested
    # gets unchoked
    downloaders = 4
    if @choke_optimistic_peer != nil &&
        @choke_optimistic_peer.peer_interested
      downloaders = 3
    end
    i = 0
    peers = @peers.select { |peer| peer.state == Peer::STATE_OK }
    peers = peers.sort { |a,b| b.rate.download <=> a.rate.download }
    peers.each { |peer|
      if peer == @choke_optimistic_peer
        # do nothing
      elsif peer.peer_interested && i < downloaders
        peer.unchoke if peer.peer_choked
        i += 1
      elsif !peer.peer_interested && i < downloaders
        peer.unchoke if peer.peer_choked
        # no count
      else
        peer.choke unless peer.peer_choked
      end
    }
  end

  # outgoing connections
  def connect_to_peers
    case @state
    when STATE_DOWNLOADING, STATE_ENDGAME
      while @peers.length < MAX_PEERS
        peer = @tracker.get_peer(@metainfo.info_hash)
        break if peer.nil?
        ip, port = peer
        connect_to_peer(ip, port)
      end
    when STATE_DONE
    end
  end

  def connect_to_peer(ip, port)
    @logger.debug("connecting to #{ip}:#{port}")
    socket   = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    # sockaddr = Socket.sockaddr_in(80, 'www.google.com')
    sockaddr = Socket.pack_sockaddr_in(port, ip.to_s)
    begin
      socket.connect_nonblock(sockaddr)
    rescue IO::WaitWritable
    end
    @peers.push(Peer.new(:logger      => @logger,
                         :my_node_id  => @my_node_id,
                         :my_reserved => [0,0].pack("NN"),
                         :socket      => socket,
                         :torrent     => self,
                         :type        => Peer::TYPE_OUTGOING))
  end
end

