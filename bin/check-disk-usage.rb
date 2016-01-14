#!/usr/bin/env ruby
#
# check-disk-usage.rb
#
# Author: Matteo Cerutti <matteo.cerutti@hotmail.co.uk>
#

require 'sensu-plugin/check/cli'
require 'json'
require 'socket'
require 'sys/filesystem'

class CheckDiskUsage < Sensu::Plugin::Check::CLI
  option :fstype,
         :description => "Comma separated list of file system type(s) (default: all)",
         :long => "--fstype <TYPE>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :ignore_fstype,
         :description => "Comma separated list of file system type(s) to ignore",
         :long => "--ignore-fstype <TYPE>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :mount,
         :description => "Comma separated list of mount point(s) (default: all)",
         :long => "--mount <MOUNTPOINT>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :mount_regex,
         :description => "Comma separated list of mount point(s) (regex)",
         :long => "--mount-regex <MOUNTPOINT>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :ignore_mount,
         :description => "Comma separated list of mount point(s) to ignore",
         :long => "--ignore-mount <MOUNTPOINT>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :ignore_mount_regex,
         :description => "Comma separated list of mount point(s) to ignore (regex)",
         :long => "--ignore-mount-regex <MOUNTPOINT>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :config_file,
         :description => "Optional configuration file (default: #{File.dirname(__FILE__)}/disk-usage.json)",
         :short => "-c <PATH>",
         :long => "--config <PATH>",
         :default => File.dirname(__FILE__) + "/disk-usage.json"

  option :warn_space,
         :description => "Warn if PERCENT or more of disk space used",
         :short => "--warn-space <PERCENT>",
         :proc => proc(&:to_i),
         :default => 85

  option :crit_space,
         :description => "Critical if PERCENT or more of disk space used",
         :short => "--crit-space <PERCENT>",
         :proc => proc(&:to_i),
         :default => 95

  option :warn_inodes,
         :description => "Warn if PERCENT or more of inodes used",
         :short => "--warn-inodes <PERCENT>",
         :proc => proc(&:to_i),
         :default => 85

  option :crit_inodes,
         :description => "Critical if PERCENT or more of inodes used",
         :short => "--crit-inodes <PERCENT>",
         :proc => proc(&:to_i),
         :default => 95

  option :handlers,
         :description => "Comma separated list of handlers",
         :long => "--handlers <HANDLER>",
         :proc => proc { |s| s.split(',') },
         :default => []

  option :warn,
         :description => "Warn instead of throwing a critical failure",
         :short => "-w",
         :long => "--warn",
         :boolean => false

  def initialize()
    super

    # discover mount points
    @mounts = get_mounts()

    @json_config = {}
    if File.exists?(config[:config_file])
      @json_config = JSON.parse(File.read(config[:config_file]))
    end
  end

  def get_mounts()
    mounts = []

    Sys::Filesystem.mounts.each do |fs|
      if config[:ignore_fstype].size > 0
        next if config[:ignore_fstype].include?(fs.mount_type)
      end

      if config[:fstype].size > 0
        next unless config[:fstype].include?(fs.mount_type)
      end

      if config[:ignore_mount].size > 0
        next if config[:ignore_mount].include?(fs.mount_point)
      end

      if config[:ignore_mount_regex].size > 0
        b = false
        config[:ignore_mount_regex].each do |mnt|
          if fs.mount_point =~ Regexp.new(mnt)
            b = true
            break
          end
        end
        next if b
      end

      if config[:mount].size > 0
        next unless config[:mount].include?(fs.mount_point)
      end

      if config[:mount_regex].size > 0
        b = true
        config[:mount_regex].each do |mnt|
          if fs.mount_point =~ Regexp.new(mnt)
            b = false
            break
          end
        end
        next if b
      end

      mounts << fs.mount_point
    end

    mounts
  end

  def send_client_socket(data)
    sock = UDPSocket.new
    sock.send(data + "\n", 0, "127.0.0.1", 3030)
  end

  def send_ok(check_name, msg)
    event = {"name" => check_name, "status" => 0, "output" => "#{self.class.name} OK: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def send_warning(check_name, msg)
    event = {"name" => check_name, "status" => 1, "output" => "#{self.class.name} WARNING: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def send_critical(check_name, msg)
    event = {"name" => check_name, "status" => 2, "output" => "#{self.class.name} CRITICAL: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def send_unknown(check_name, msg)
    event = {"name" => check_name, "status" => 3, "output" => "#{self.class.name} UNKNOWN: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def run
    problems = 0

    @mounts.uniq.each do |mount|
      stat = Sys::Filesystem.stat(mount)

      if stat.bytes_total > 0
        if @json_config.has_key?('mountpoints') and @json_config['mountpoints'].has_key?(mount) and @json_config['mountpoints'][mount].has_key?("warn_space")
          warn_space = @json_config['mountpoints'][mount]['warn_space']
        else
          warn_space = config[:warn_space]
        end

        if @json_config.has_key?('mountpoints') and @json_config['mountpoints'].has_key?(mount) and @json_config['mountpoints'][mount].has_key?("crit_space")
          crit_space = @json_config['mountpoints'][mount]['crit_space']
        else
          crit_space = config[:crit_space]
        end

        percent_bytes_used = (100.0 - (100.0 * stat.bytes_free / stat.bytes_total)).round(2)

        check_name = "disk-usage-space-#{mount.gsub('/', '_')}"
        msg = "Filesystem #{mount} space usage is #{percent_bytes_used}%"

        if percent_bytes_used >= crit_space
          msg += ", expected < #{crit_space}%"
          send_critical(check_name, msg)
          problems += 1
        elsif percent_bytes_used >= warn_space
          msg += ", expected < #{warn_space}%"
          send_warning(check_name, msg)
          problems += 1
        else
          send_ok(check_name, msg)
        end
      end

      if stat.inodes > 0
        if @json_config.has_key?('mountpoints') and @json_config['mountpoints'].has_key?(mount) and @json_config['mountpoints'][mount].has_key?("warn_inodes")
          warn_inodes = @json_config['mountpoints'][mount]['warn_inodes']
        else
          warn_inodes = config[:warn_inodes]
        end

        if @json_config.has_key?('mountpoints') and @json_config['mountpoints'].has_key?(mount) and @json_config['mountpoints'][mount].has_key?("crit_inodes")
          crit_inodes = @json_config['mountpoints'][mount]['crit_inodes']
        else
          crit_inodes = config[:crit_inodes]
        end

        percent_inodes_used = (100.0 - (100.0 * stat.inodes_free / stat.inodes)).round(2)

        check_name = "disk-usage-inodes-#{mount.gsub('/', '_')}"
        msg = "Filesystem #{mount} inodes usage is #{percent_inodes_used}%"

        if percent_inodes_used >= crit_inodes
          msg += ", expected < #{crit_inodes}%"
          send_critical(check_name, msg)
          problems += 1
        elsif percent_inodes_used >= warn_inodes
          msg += ", expected < #{warn_inodes}%"
          send_warning(check_name, msg)
          problems += 1
        else
          send_ok(check_name, msg)
        end
      end
    end

    if problems > 0
      message "Found #{problems} problems"
      warning if config[:warn]
      critical
    else
      ok "All filesystems (#{@mounts.join(', ')}) are OK"
    end
  end
end
