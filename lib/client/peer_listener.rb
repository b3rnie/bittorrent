require_relative 'peer'
require_relative 'socket_buffer'
require_relative 'wire_protocol'

class PeerListener
  attr_reader :socket, :peers

  def initialize(options = {})
    @logger     = options[:logger]
    @my_node_id = options[:my_node_id]
    @port       = options[:port]
    @torrents   = options[:torrents]
    @peers      = []
    initialize_listen_socket
  end

  def initialize_listen_socket
    @socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    @socket.bind(Addrinfo.tcp("0.0.0.0", @port))
    @socket.listen(10)
  end

  def ready_to_write?; false end
  def ready_to_read?;  true  end

  def try_read
    begin
      socket, addrinfo = @socket.accept_nonblock
      @logger.info("received incoming connection from " + addrinfo.to_s)
      peer = Peer.new(:logger       => @logger,
                      :my_node_id   => @my_node_id,
                      :my_reserved  => [0,0].pack("NN"),
                      :socket       => socket,
                      :state        => Peer::STATE_WAITING_FOR_HANDSHAKE,
                      :torrents     => @torrents,
                      :type         => Peer::TYPE_INCOMING)
      @peers.push(peer)
    rescue IO::WaitReadable, Errno::EINTR
    end
  end

  def update
    @peers.each { |peer| peer.update }
    @peers.reject! { |peer|
      if peer.state == Peer::STATE_OK
        if torrent = find_torrent(peer.info_hash)
          torrent.peers.push(peer)
        else
          peer.stop
        end
      end
      peer.state == Peer::STATE_OK || peer.stop?
    }
  end

  private
  def find_torrent(info_hash)
    @torrents.find { |torrent| torrent.info_hash == info_hash }
  end
end
