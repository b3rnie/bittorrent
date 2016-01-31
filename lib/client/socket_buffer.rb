class SocketBuffer
  attr_reader :in, :out, :socket

  SOCKET_BUFFER_MAX_SIZE      = 262144
  SOCKET_BUFFER_STATUS_OPEN   = 0
  SOCKET_BUFFER_STATUS_CLOSED = 1

  def initialize(options = {})
    @logger = options[:logger]
    @rate   = options[:rate]
    @socket = options[:socket]
    @in     = ""
    @out    = ""
    @status = SOCKET_BUFFER_STATUS_OPEN
  end

  def is_open?
    @status == SOCKET_BUFFER_STATUS_OPEN
  end

  def ready_to_read?
    is_open? && @in.length < SOCKET_BUFFER_MAX_SIZE
  end

  def ready_to_write?
    is_open? && !@out.empty?
  end

  def try_read
    case @status
      when SOCKET_BUFFER_STATUS_OPEN
      begin
        data = @socket.read_nonblock(65536)
        if data.empty?
          @status = SOCKET_BUFFER_STATUS_CLOSED
          close
        end
        @in.concat(data)
        @rate.register_download(data.length)
      rescue IO::WaitReadable
      rescue EOFError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT => e
        @logger.info(e.to_s)
        @status = SOCKET_BUFFER_STATUS_CLOSED
        close
      end
    when SOCKET_BUFFER_STATUS_CLOSED
      @logger.info("trying to read from a closed socket")
    end
  end

  def try_write
    fail "nothing to write" if @out.empty?
    case @status
    when SOCKET_BUFFER_STATUS_OPEN
      begin
        length = @socket.write_nonblock(@out)
        @out = @out[length..-1]
        @rate.register_upload(length)
      rescue IO::WaitWritable, Errno::EINTR
      rescue Errno::EPIPE => e
        @logger.info(e.to_s)
        @status = SOCKET_BUFFER_STATUS_CLOSED
        close
      end
    when SOCKET_BUFFER_STATUS_CLOSED
      @logger.info("trying to write to a closed socket")
    end
  end

  def advance(length)
    fail "cant advance past size" if length > @in.length
    @in = @in[length..-1]
  end

  def out_full?
    @out.length >= SOCKET_BUFFER_MAX_SIZE
  end
  
  def concat(data)
    @out.concat(data)
  end

  def close
    if @socket
      @socket.close
      @socket = nil
    end
  end
end
