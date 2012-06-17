#!/usr/bin/env ruby
# Version: 0.01a build 3 (2012-06-17)

require 'optparse'
require 'net/telnet'

# Fujian Star-Net AR800 ADSL Router interaction
class StarnetRouter
	@connected = false
	@hostname = nil
	@client = nil
	@nvram = nil

	# Create a connection and login (default credentials is admin:admin)
	def initialize(hostname, password = 'admin')
		begin
			@hostname = hostname
			puts "Creating a connection to #{hostname}"
			@client = Net::Telnet.new('Host' => hostname, 'Port' => 23, 'Prompt' => />|Login incorrect/)
			# These are hardcoded parameters
			result = @client.login({
				'Name' => 'admin',
				'Password' => password,
				'LoginPrompt' => /STAR-NET ADSL2\+ Router\nLogin:|Router v1.5\nLogin:|MSW41p1 v2.5\nLogin:/,
				'PasswordPrompt' => /Password:/
			})
			# Raise an exception if could not login
			error "Failed to login!" unless result =~ />/
			@connected = true
		rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError, Timeout::Error
			error "Failed to connect to #{hostname}"
		end
	end
    
	# Get the host name
	def hostname()
		@hostname
	end
    
	# Check if we're connected to a host
	def connected?()
		@connected
	end
    
	# Execute an arbitrary command
	def raw_command(cmd)
		error "Not connected" unless @connected
		result = @client.cmd(cmd).split("\n")
		result.shift
		result.pop
		return result
	end

	# Show an ARP-table using 'arp show' command
	def arp_show()
		error "Not connected" unless @connected
		result = @client.cmd('arp show').split("\n")
		result.shift(3)
		result.pop(2)
		return result
	end

	# Show MAC table using 'lanhosts show all'
	def mac_show()
		error "Not connected" unless @connected
		result = @client.cmd('lanhosts show all').split("\n")
		result.shift(3)
		result.pop(1)
		return result
	end

	# Ping a set of hosts given as an array (the default timeout is 30 seconds)
	# Return an array of alive hosts
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

	# Returns a string with /var/nvram contents
	# Optionally output a message
	def get_nvram(msg = '')
		# Do this only once
		if @nvram.nil?
			error "Not connected" unless @connected
			puts msg if msg != ''
			result = @client.cmd('cat /var/nvram').split("\n")
			result.shift
			@nvram = result[0] if result
		end
		return @nvram
	end
end

# Output an error and terminate with error code 1
def error(msg = 'Error')
	puts msg
	exit 1
end

def options_parse()
	options = {}
	begin
		OptionParser.new do |opts|
			opts.banner = "Star-Net AR800 Management utility\nUsage: #{$0} [options] <target>"
			# Password
			options[:password] = nil
			opts.on('-p PASSWORD', '--password PASSWORD', 'Password to login with') do |password|
				options[:password] = password
			end
			# Raw command
			options[:raw] = nil
			opts.on('-r CMD', '--raw CMD', 'Execute an arbitrary command on remote host') do |cmd|
				options[:raw] = cmd
			end
			# Show ARP table
			options[:arpshow] = false
			opts.on('-A', '--arpshow', 'Show ARP table') do
				options[:arpshow] = true
			end
			# Show MAC table
			options[:macshow] = false
			opts.on('-M', '--macshow', 'Show MAC table') do
				options[:macshow] = true
			end
			# Ping HOSTS
			options[:ping] = nil
			opts.on('-P HOSTS', '--ping HOSTS', 'Ping a comma-separated set of hostnames') do |hosts|
				options[:ping] = hosts
			end
			# Get WPS PIN
			options[:wps_device_pin] = false
			opts.on('-W', '--wps-device-pin', 'Get a WPS PIN from the device') do
				options[:wps_device_pin] = true
			end
                        # Get NVRAM
                        options[:nvram] = false
                        opts.on('-N', '--nvram', 'Get /var/nvram file contents') do
                                options[:nvram] = true
                        end
			# Help
			opts.on('-h', '--help', 'Display usage information') do
				puts opts
				exit
			end
		end.parse!
	rescue OptionParser::MissingArgument
		error "Option is missing an argument!"
	rescue OptionParser::InvalidOption
		error "Invalid option!"
	end
	options
end

# Main code flow
options = options_parse()
hostname = ARGV.shift
error "Target hostname required!" unless hostname

if options[:password]
	sn = StarnetRouter.new(hostname, options[:password])
else
	sn = StarnetRouter.new(hostname)
end
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

if options[:nvram]
	nvram = sn.get_nvram('Reading /var/nvram ...')
	puts nvram if nvram
end

if options[:wps_device_pin]
	nvram = sn.get_nvram()
	result = /wps_device_pin=(\d{8})/.match(nvram) if nvram
	puts "WPS PIN: #{result[1]}" if result
end
