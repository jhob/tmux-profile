#!/usr/bin/env ruby

require 'yaml'

require 'optparse'

def check_deps
  raise "Please install tmux" unless `which tmux` != ""
end


def current_session
  `test -n "\${TMUX+set}" && tmux display-message -p '#S'`.strip
end

def session_exists? name
  # tmux has-session doesn't work as it returns true for substrings
  `tmux list-sessions -F "#S"`.split("\n").include? name
end


# Runs command in current shell
def run cmd, args=[]
  cmd = "#{cmd} #{args.join ' '}".strip
  puts cmd
  `#{cmd}`
end


# Sends keys to tmux pane
def send_to_pane pane, cmd
  cmd = "'#{cmd}'".gsub(/'''/, '"\'"')
  cmd = "#{cmd} 'Enter'"
  run "tmux send-keys", ["-t #{pane}", cmd]
end


# Runs a command within shell inside tmux
def run_in_pane pane, cmds
  cmds = [ cmds ] unless cmds.is_a? Array
  cmds.each do |cmd|
    send_to_pane pane, cmd
  end
end

def helper_dir
  File.expand_path('./helpers', File.dirname(__FILE__))
end

def profile_dir
  File.expand_path('~/.tmux-profiles', File.dirname(__FILE__))
end

def system_profile_dir
  File.expand_path('./profiles', File.dirname(__FILE__))
end

def load_helpers
  out = ''
  Dir.glob "#{helper_dir}/*.yaml" do |filename|
    key = File.basename(filename).gsub '.yaml', ''
    out = "helper_#{key}: &#{key}\n"
    File.readlines(filename).each do |line|
      out += '  ' + line
    end
  end
  out
end

# Loads profile by name
def load_profile profile_name, attach_to=nil

  default_window = { "name" => "default" }
  yaml_data = ''

  yaml_data += load_helpers

  begin
    yaml_data +=  File.read "#{profile_dir}/#{profile_name}.yaml"
  rescue
    begin
      yaml_data +=  File.read "#{system_profile_dir}/#{profile_name}.yaml"
    rescue
      raise "Profile '#{profile_name}' doesn't exist. Is it in your '~/.tmux-profiles' directory?"
    end
  end

  begin
    profile = YAML.load yaml_data
  rescue Exception => e
    raise e
    raise "Profile '#{profile_name}' isn't valid YAML"
  end

  # initialize all sessions
  profile["sessions"].each do |session|

    if session_exists? session["name"]
      puts "Session '#{session["name"]}' exists."
      next
    end

    window = session["windows"].first || default_window

    # get current terminal height/width
    w = `tput cols`.strip
    h = `tput lines`.strip

    current_dir = session["dir"] || window["dir"]
    
    # run setup command for session
    setup_cmd = session["setup_cmd"]
    puts setup_cmd
    if setup_cmd
      run "cd #{current_dir} && #{setup_cmd}"
    end

    # create session
    args = []
    args << "-s #{session["name"]}"
    args << "-n #{window["name"]}"
    args << "-c #{current_dir}" unless current_dir.nil?
    args << "-x #{w}"
    args << "-y #{h}"
    args << "-d"
    run "tmux new-session", args

    # create more windows
    session["windows"][1..-1].each do |new_window|
      current_dir = new_window["dir"] || session["dir"]
      args = []
      args << "-t #{session["name"]}"
      args << "-n #{new_window["name"]}"
      args << "-c #{current_dir}" unless current_dir.nil?
      args << "-d"
      run "tmux new-window", args
    end

    # initialize windows
    session["windows"].each do |new_window|
      n = "#{session["name"]}:#{new_window["name"]}"

      run_in_pane n, new_window["cmd"] unless new_window["cmd"].nil?
      send_to_pane n, new_window["send"] unless new_window["send"].nil?

      panes = new_window["panes"] || []
      panes.each do |pane|
        current_dir = pane["dir"] || new_window["dir"] || session["dir"]
        args = []
        args << "-t #{n}"
        args << "-c #{current_dir}" unless current_dir.nil?
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
  if attach_to.nil?
    profile["sessions"].each do |session|
      if session["attach"]
          attach_to = session["name"]
          break
      end
    end
  end

  unless attach_to.nil?
    if current_session.empty?
      run "tmux attach", ["-t #{attach_to}"]
    elsif current_session != attach_to
      run "tmux switch-client", ["-t #{attach_to}"]
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
    profile_name, attach_to = ARGV.first.split ":"
    load_profile profile_name, attach_to
  else
    puts parser
  end
end

