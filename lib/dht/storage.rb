require 'json'
require 'leveldb'
require 'fileutils'

class Storage
  def initialize(options = {})
    @data_dir = options[:data_dir]
    initialize_directories()
    initialize_database()
  end

  def initialize_directories()
    @dir_config     = File.join(@data_dir, "config")
    @dir_routing    = File.join(@data_dir, "routing")
    @dir_peers      = File.join(@data_dir, "peers")

    FileUtils.mkdir_p(@dir_config)
    FileUtils.mkdir_p(@dir_routing)
    FileUtils.mkdir_p(@dir_peers)
  end

  def initialize_database()
    @db_config      = LevelDB::DB.new(@dir_config)
    @db_routing     = LevelDB::DB.new(@dir_routing)
    @db_peers       = LevelDB::DB.new(@dir_peers)
  end

  def set_routing_table(instance, index, bucket)
    @db_routing.put(instance + "_" + index.to_s, bucket)
  end

  def get_routing_table(instance, index)
    @db_routing.get(instance + "_" + index.to_s)
  end

  def get_config(instance, key)
    @db_config.get(instance + "_" + key)
  end

  def set_config(instance, key, value)
    @db_config.put(instance + "_" + key, value)
  end

  def set_peer(info_hash, id, peer)
    @db_peers.put(info_hash + "_" + id, peer)
  end

  def delete_peer(info_hash, id)
    @db_peers.delete(info_hash + "_" + id)
  end

  def each_peer(&block)
    @db_peers.each { |k,v|
      info_hash, id = k.split("_")
      block.call(info_hash, id, v)
    }
  end
end
