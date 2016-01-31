#!/usr/bin/ruby
require 'set'
require_relative '../utils/periodic'

class DirWatcher
  def initialize(options = {})
    @metainfo_path = options[:metainfo_path]
    @my_node_id    = options[:my_node_id]
    @output_path   = options[:output_path]
    @interval      = options[:interval]
    @logger        = options[:logger]
    @torrents      = options[:torrents]
    @tracker       = options[:tracker]
    @content       = Set.new
    @periodic      = Periodic.new(@interval => proc { scan_path })
  end

  def update
    @periodic.update(Time.now.to_i)
  end

  def scan_path
    find_changes.each { |event, file|
      case event
      when :created then start_torrent(file)
      when :deleted then stop_torrent(file)
      end
    }
  end
  private
  def find_changes
    changes = []
    files = Dir.entries(@metainfo_path).map { |file|
      File.join(@metainfo_path, file)
    }.reject { |file|
      File.directory?(file)
    }
    files.each { |file|
      unless @content.include?(file)
        @content.add(file)
        changes.push([:created, file])
      end
    }
    @content.keep_if { |file|
      if files.include?(file)
        true
      else
        changes.push([:deleted, file])
        false
      end
    }
    changes
  end

  def start_torrent(file)
    @logger.info("starting torrent " + file)
    torrent = Torrent.new(:logger        => @logger,
                          :metainfo_file => file,
                          :my_node_id    => @my_node_id,
                          :output_path   => @output_path,
                          :tracker       => @tracker)
    @torrents.push(torrent)
  end

  def stop_torrent(file)
    @logger.info("stopping torrent " + file)
    if index = @torrents.find_index { |torrent|
        torrent.metainfo_file == file
      }
      torrent = @torrents.delete_at(index)
      torrent.stop
    else
      # bad fail
    end
  end

  
end
