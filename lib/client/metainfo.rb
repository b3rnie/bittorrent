#!/usr/bin/ruby

require "bencode"
require 'digest/sha1'
require_relative '../utils/conversions'

class MetainfoException < Exception; end

class Metainfo
  attr_reader :announce
  attr_reader :piece_length, :pieces, :info_hash, :total_length

  attr_reader :name, :length # single
  attr_reader :name, :files # multi

  def initialize(options = {})
    file = options[:file]
    bin  = File.read(file)
    dict = BEncode.load(bin)
    info = dict["info"]
    load_announce(dict)
    load_common_part(info)
    load_single_multi_part(info)
  end

  def is_single_file?
    @length != nil
  end

  private
  def load_announce(dict)
    # TODO: support announce-list
    @announce = [dict["announce"]]
  end

  def load_common_part(info)
    @piece_length = info["piece length"]
    @pieces       = info["pieces"].chars.each_slice(20)
      .map(&:join)
      .map { |piece| Conversions.binary_id_to_hex(piece) }
    @info_hash    = Digest::SHA1.hexdigest(info.bencode).rjust(40, "0")
  end

  def load_single_multi_part(info)
    @name = info["name"]
    if info.has_key?("length")
      @length       = info["length"]
      @total_length = info["length"]
    else
      @total_length = 0
      @files = info["files"].map { |file|
        @total_length += file["length"]
        [file["path"], file["length"]]
      }
    end
  end
end
