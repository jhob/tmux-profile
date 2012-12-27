require 'yaml'


def check_deps
    raise "Please install tmux" unless `which tmux` != ""
end


def session_exists? name
    system "tmux has-session -t #{name}"
end


# Runs command in current shell
def run cmd
    puts cmd
    `#{cmd}`
end


# Sends keys to tmux pane
def send_to_pane pane, keys
    keys = cmds.join " " if keys.is_a? Array
    run "tmux send-keys -t #{pane} #{keys}"
end


# Runs a command within shell inside tmux
def run_in_pane pane, cmds
    cmds = [ cmds ] unless cmds.is_a? Array
    cmds.each do |cmd|
        cmd = cmd.split("").join("' '")
        cmd = cmd.gsub /'''/, '"\'"'
        send_to_pane pane, "'#{cmd}' Enter"
    end
end


# Loads profile by name
def load_profile profile_name

    default_window = { "name" => "default" }

    begin
        profile_dir = File.expand_path('./profiles', File.dirname(__FILE__))
        profile = YAML.load_file "#{profile_dir}/#{profile_name}.yaml"
    rescue
        raise "Profile '#{profile_name}' doesn't exist"
    end

    # initialize all sessions
    profile["sessions"].each do |session|

        if session_exists? session["name"]
            puts "Session '#{session["name"]}' already exists. Skipping."
            return
        end

        dir = session["default-path"]
        
        window = session["windows"].first || default_window

        # get current terminal height/width
        w = `tput cols`.strip
        h = `tput lines`.strip

        # create session
        run "cd #{dir} ; tmux new-session -s #{session["name"]} -n #{window["name"]} -x #{w} -y #{h} -d"

        # set default directory
        run "tmux set-option -t #{session["name"]} default-path \"#{dir}\""

        # create more windows
        session["windows"][1..-1].each do |window|
            run "tmux new-window -t #{session["name"]} -n #{window["name"]} -d"
        end

        # initialize windows
        session["windows"].each do |window|
            n = "#{session["name"]}:#{window["name"]}"
            cmds = window["cmd"]
            run_in_pane n, cmds unless cmds.nil?
            send = window["send"]
            send_to_pane n, send unless send.nil?
            panes = window["panes"] || []
            panes.each do |pane|
                flags = "-#{ pane["split"][0] || "h" } "
                flags += "-l #{pane["size"]} " unless pane["size"].nil?
                run "tmux split-window -t #{n} #{flags}"
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
            run "tmux attach -t #{session["name"]}"
            break
        end
    end

end


# main
check_deps()
load_profile ARGV.first

