#!/usr/bin/env ruby
# Version: 0.01a build 2 (2012-06-02)

require 'optparse'
require 'net/telnet'

# Fujian Star-Net AR800 ADSL Router interaction
class StarnetRouter
	@connected = false
	@hostname = nil
	@client = nil

	# Create a connection and login
	def initialize(hostname)
		begin
			@hostname = hostname
			puts "Creating a connection to #{hostname}"
			@client = Net::Telnet.new('Host' => hostname, 'Port' => 23, 'Prompt' => />|Login incorrect/)
			# These are hardcoded parameters
			result = @client.login({
				'Name' => 'admin',
				'Password' => 'admin',
				'LoginPrompt' => /STAR-NET ADSL2\+ Router\nLogin:|Router v1.5\nLogin:|MSW41p1 v2.5\nLogin:/,
				'PasswordPrompt' => /Password:/
			})
			# Raise an exception if could not login
			error "Failed to login!" unless result =~ />/
			@connected = true
		rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error
			error "Failed to connect to #{hostname}"
		end
	end
    
	def hostname()
		@hostname
	end
    
	def connected?()
		@connected
	end
    
	def raw_command(cmd)
		error "Not connected" unless @connected
		result = @client.cmd(cmd).split("\n")
		result.shift
		result.pop
		return result
	end

	def arp_show()
		error "Not connected" unless @connected
		result = @client.cmd('arp show').split("\n")
		result.shift(3)
		result.pop(2)
		return result
	end

	def mac_show()
		error "Not connected" unless @connected
		result = @client.cmd('lanhosts show all').split("\n")
		result.shift(3)
		result.pop(1)
		return result
	end

	def ping(hosts = [])
		error "Not connected" unless @connected
		alive_hosts = []
		hosts.each do |i|
			result = @client.cmd({'String' => "ping -c 1 #{i}", 'Timeout' => 30}).split("\n")
			result.shift(2)
			result.pop
			alive_hosts << i unless result.grep(/icmp_seq/).empty?
		end
		return alive_hosts
	end
end

def error(msg = 'Error')
	puts msg
	exit 1
end

def options_parse()
	options = {}
	OptionParser.new do |opts|
		opts.banner = "Star-Net AR800 Management utility\nUsage: #{$0} [options] <target>"
		# Raw command
		options[:raw] = nil
		opts.on('-r CMD', '--raw CMD', 'Execute an arbitrary command on remote host') do |cmd|
			options[:raw] = cmd
		end
		# Show ARP table
		options[:arpshow] = false
		opts.on('-a', '--arpshow', 'Show ARP table') do
			options[:arpshow] = true
		end
		# Show MAC table
		options[:macshow] = false
		opts.on('-m', '--macshow', 'Show MAC table') do
			options[:macshow] = true
		end
		# Ping HOSTS
		options[:ping] = nil
		opts.on('-p HOSTS', '--ping HOSTS', 'Ping a comma-separated set of hostnames') do |hosts|
			options[:ping] = hosts
		end
		# Help
		opts.on('-h', '--help', 'Display usage information') do
			puts opts
			exit
		end
	end.parse!
	options
end

# Main code flow
options = options_parse()
hostname = ARGV.shift
error "Target hostname required!" unless hostname
sn = StarnetRouter.new(hostname)
error "Could not connect to #{hostname}" unless sn.connected?

# Raw command
if options[:raw]
	puts "[*] Executing: '#{options[:raw]}'"
	sn.raw_command(options[:raw]).each do |i|
		puts i
	end
end

if options[:arpshow]
	puts "[*] Executing: 'arp show' command"
	sn.arp_show.each do |i|
		ip, hw_type, flags, hw_address, mask, device, connect_time = i.split(' ')
		puts "IP = #{ip}, MAC = #{hw_address}"
	end
end

if options[:macshow]
	puts "Executing: 'lanhosts show all' command"
	sn.mac_show.each do |i|
		mac, ip, time, host = i.split(' ')
		puts "MAC = #{mac}, IP = #{ip}, Lease time = #{time}, Hostname = #{host}"
	end
end

if options[:ping]
	puts "[*] Executing 'ping' command"
	result = sn.ping(options[:ping].split(","))
	result.each do |i|
		puts "Found alive host: #{i}"
	end
end
