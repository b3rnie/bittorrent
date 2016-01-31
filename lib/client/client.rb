#!/usr/bin/ruby

require 'dbm'
require 'fileutils'
require 'logger'
require 'ruby-prof'
require 'securerandom'
require 'socket'
require_relative 'dirwatcher'
require_relative 'metainfo'
require_relative 'peer_listener'
require_relative 'torrent'
require_relative 'tracker'

class Client
  def initialize(options = {})
    @logfile      = options[:logfile]
    @metainfo     = options[:metainfo]
    @path         = options[:path]
    @port         = options[:port]
    @session      = options[:session]
    @tracker_port = options[:tracker_port]
    @torrents     = []
    setup_directories
    setup_session_database
    setup_logging
    setup_tracker
    setup_listener
    setup_dirwatcher
    @logger.info("using node id " + @db["id"])
  end

  def run
    # RubyProf.measure_mode = RubyProf::CPU_TIME
    # RubyProf.start
    # i = 0
    while true
      # break if i == 1000
      read  = select_on_sockets { |obj| obj.ready_to_read? }
      write = select_on_sockets { |obj| obj.ready_to_write? }
      if o = IO::select(read.keys, write.keys, [], 1)
        o[0] && do_reads(o[0], read)
        o[1] && do_writes(o[1], write)
      end
      update
      # i += 1
    end
    # result = RubyProf.stop
    ## print a flat profile to text
    # printer = RubyProf::FlatPrinter.new(result)
    # printer.print(STDOUT)
  end

  private
  # init
  def setup_directories
    unless File.directory?(File.dirname(@logfile))
      FileUtils.mkdir_p(File.dirname(@logfile))
    end
    FileUtils.mkdir_p(@metainfo) unless File.directory?(@metainfo)
    FileUtils.mkdir_p(@path)     unless File.directory?(@path)
    FileUtils.mkdir_p(@session)  unless File.directory?(@session)
  end

  def setup_session_database
    @db = DBM.open(File.join(@session, "config"), 0666, DBM::WRCREAT)
    unless @db.has_key?("id")
      id        = "XX" + SecureRandom.random_bytes(18)
      @db["id"] = Conversions.binary_id_to_hex(id)
    end
  end

  def setup_logging
    @logger = Logger.new(@logfile, 'daily')
    @logger.sev_threshold = Logger::DEBUG
  end

  def setup_tracker
    @tracker = Tracker.new(:logger     => @logger,
                           :my_node_id => @db["id"],
                           :port       => @tracker_port)
  end

  def setup_listener
    @listener = PeerListener.new(:logger     => @logger,
                                 :my_node_id => @db["id"],
                                 :port       => @port,
                                 :torrents   => @torrents)
  end

  def setup_dirwatcher
    @dirwatcher = DirWatcher.new(:interval      => 1,
                                 :logger        => @logger,
                                 :metainfo_path => @metainfo,
                                 :my_node_id    => @db["id"],
                                 :output_path   => @path,
                                 :torrents      => @torrents,
                                 :tracker       => @tracker)
  end

  # select/update loop
  def select_on_sockets
    peers       = @torrents.map { |torrent| torrent.peers }.flatten
    peers_setup = @listener.peers
    select_on   = [peers, peers_setup,
                   [@listener],
                   [@tracker]]
      .flatten.select { |o|
      yield(o)
    }
    select_on.map { |o| [o.socket, o] }.to_h
  end

  def do_reads(sockets, hash)
    sockets.each { |socket| hash[socket].try_read }
  end

  def do_writes(sockets, hash)
    sockets.each { |socket| hash[socket].try_write }
  end

  def update
    @logger.debug("update")
    @listener.peers.each { |peer| peer.update }
    @listener.update
    @torrents.each { |torrent| torrent.update }
    @dirwatcher.update
    @tracker.update
  end
end
