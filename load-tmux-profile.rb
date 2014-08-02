#!/usr/bin/env ruby
#
require 'yaml'
require 'optparse'


def check_deps
    raise "Please install tmux" unless `which tmux` != ""
end


def session_exists? name
    system "tmux has-session -t #{name} 2> /dev/null"
end


# Runs command in current shell
def run cmd, args=[]
    cmd = "#{cmd} #{args.join ' '}".strip
    puts cmd
    `#{cmd}`
end


# Sends keys to tmux pane
def send_to_pane pane, keys
    keys = [ keys ] unless keys.is_a? Array
    keys = keys.map { |key|
        "'#{key}'".gsub /'''/, '"\'"'
    }
    run "tmux send-keys", ["-t #{pane}", keys.join(' ')]
end


# Runs a command within shell inside tmux
def run_in_pane pane, cmds
    cmds = [ cmds ] unless cmds.is_a? Array
    cmds.each do |cmd|
        keys = cmd.split("")
        keys << "Enter"
        send_to_pane pane, keys
    end
end

def profile_dir
    File.expand_path('./profiles', File.dirname(__FILE__))
end


# Loads profile by name
def load_profile profile_name

    default_window = { "name" => "default" }

    begin
        profile = YAML.load_file "#{profile_dir}/#{profile_name}.yaml"
    rescue
        raise "Profile '#{profile_name}' doesn't exist"
    end

    # initialize all sessions
    profile["sessions"].each do |session|

        if session_exists? session["name"]
            puts "Session '#{session["name"]}' already exists. Skipping."
            next
        end

        window = session["windows"].first || default_window

        # get current terminal height/width
        w = `tput cols`.strip
        h = `tput lines`.strip

        # create session
        window["dir"] ||= session["dir"]
        args = []
        args << "-s #{session["name"]}"
        args << "-n #{window["name"]}"
        args << "-c #{window["dir"]}" unless window["dir"].nil?
        args << "-x #{w}"
        args << "-y #{h}"
        args << "-d"
        run "tmux new-session", args

        # create more windows
        session["windows"][1..-1].each do |window|
            window["dir"] ||= session["dir"]
            args = []
            args << "-t #{session["name"]}"
            args << "-n #{window["name"]}"
            args << "-c #{window["dir"]}" unless window["dir"].nil?
            args << "-d"
            run "tmux new-window", args
        end

        # initialize windows
        session["windows"].each do |window|
            n = "#{session["name"]}:#{window["name"]}"

            run_in_pane n, window["cmd"] unless window["cmd"].nil?
            send_to_pane n, window["send"] unless window["send"].nil?

            panes = window["panes"] || []
            panes.each do |pane|
                pane["dir"] ||= window["dir"]
                args = []
                args << "-t #{n}"
                args << "-c #{pane["dir"]}" unless pane["dir"].nil?
                args << "-#{ pane["split"][0] || "h" } "
                args << "-l #{pane["size"]} " unless pane["size"].nil?
                run "tmux split-window", args
                cmds = pane["cmd"]
                run_in_pane n, cmds unless cmds.nil?
                send = pane["send"]
                send_to_pane n, send unless send.nil?
            end
        end

    end

    # attach first specified session
    profile["sessions"].each do |session|
        if session["attach"]
            run "tmux attach", ["-t #{session["name"]}"]
            break
        end
    end

end


options = {}
parser = OptionParser.new do |opts|

  opts.banner = "Usage: #{ File.basename __FILE__ } [-l] PROFILE"

  opts.on("-l", "--list", "List available profiles") do |l|
    options[:list] = l
  end

end


if __FILE__ == $0

    check_deps()
    parser.parse! ARGV

    if options[:list]
        puts Dir.new(profile_dir)
                .select { |f| f =~ /\.yaml$/ }
                .map { |f| f.sub ".yaml", "" }
                .join "\n"
    elsif ARGV.length > 0
		run "tmux start-server"
        load_profile ARGV.first
    else
        puts parser
    end
end

