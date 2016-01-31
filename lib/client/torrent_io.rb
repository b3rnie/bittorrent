require 'fileutils'
require_relative 'block'

class TorrentIO
  BLOCK_SIZE = 2**14 # 16384 bytes

  TorrentFile = Struct.new(:path, :start, :length, :file)

  def initialize(options = {})
    @logger   = options[:logger]
    @path     = options[:path]
    @metainfo = options[:metainfo]
    build_file_list
    open_files
  end

  def write(piece, start, data)
    files = find_files(piece, start, data.length)
    files.inject(0) { |data_offset, file|
      fd = @files[file[:index]][:file]
      fd.seek(file[:start], IO::SEEK_SET)
      fd.write(data[data_offset, file[:length]])
      data_offset + file[:length]
    }
  end

  def read(piece, start, length)
    files = find_files(piece, start, length)
    files.inject(data = "") { |data, file|
      if data
        fd = @files[file[:index]][:file]
        fd.seek(file[:start], IO::SEEK_SET)
        file_data = fd.read(file[:length])
        if file_data.nil? || file_data.length != file[:length]
          nil
        else
          data + file_data
        end
      end
    }
  end

  def close
    @files.each { |file| file[:file].close }
  end

  def check_all_pieces
    @metainfo.pieces.each_with_index{ |sha1, index|
      if sha1_for_piece(index) == sha1
        yield(index)
      end
    }
  end

  def check_piece(piece)
    if sha1_for_piece(piece) == @metainfo.pieces[piece]
      yield
    end
  end

  def blocks(piece)
    piece_length          = piece_length(piece)
    number_of_full_blocks = piece_length / BLOCK_SIZE
    size_last_block       = piece_length % BLOCK_SIZE
    blocks = (0..number_of_full_blocks-1).map { |i|
      Block.new(piece, i * BLOCK_SIZE, BLOCK_SIZE)
    }
    if size_last_block != 0
      blocks.push(Block.new(piece,
                            number_of_full_blocks * BLOCK_SIZE,
                            size_last_block))
    end
    blocks
  end

  def is_valid_block?

  end

  def piece_length(piece)
    start = @metainfo.piece_length * piece
    if start + @metainfo.piece_length > @metainfo.total_length
      @metainfo.total_length - start
    else
      @metainfo.piece_length
    end
  end

  def build_file_list
    if @metainfo.is_single_file?
      file   = File.join(@path, normalize(@metainfo.name))
      @files = [TorrentFile.new(file, 0, @metainfo.length, nil)]
    else
      start  = 0
      @files = @metainfo.files.map { |path, length|
        file = File.join(*([@path] +
                           [normalize(@metainfo.name)] +
                           path.map { |e| normalize(e) }))
        file_start = start
        start += length
        TorrentFile.new(file, file_start, length, 0)
      }
      puts @files
    end
  end

  def open_files
    @files.map { |file|
      FileUtils.mkdir_p(File.dirname(file[:path]))
      if File.exists?(file[:path])
        file[:file] = File.open(file[:path], "r+b")
      else
        file[:file] = File.open(file[:path], "w+b")
      end
      file
    }
  end

  def find_files(piece, start, length)
    abs_start = piece * @metainfo.piece_length + start
    index     = @files.find_index { |file|
      file[:start] <= abs_start &&
      file[:start] + file[:length] > abs_start
    }
    piece_start = abs_start - @files[index][:start]
    accumulated = 0
    offsets     = []
    while accumulated != length
      file        = @files[index]
      max_len     = file[:length] - piece_start
      len         =
        if accumulated + max_len > length
          length - accumulated
        else
          max_len
        end
      offsets.push({:index => index,
                    :start => piece_start,
                    :length => len})
      piece_start  = 0
      accumulated += len
      index       += 1
    end
    offsets
  end

  def normalize(s)
    s.gsub(/\.+/, ".").gsub(/[^A-Za-z0-9\-_ \[\]\(\)\&\.,]/, "")
  end

  def sha1_for_piece(piece)
    start_offset = piece * @metainfo.piece_length
    len =
      if start_offset + @metainfo.piece_length > @metainfo.total_length
        @metainfo.total_length - start_offset
      else
        @metainfo.piece_length
      end
    if data = read(piece, 0, len)
      Digest::SHA1.hexdigest(data)
    end
  end
end

