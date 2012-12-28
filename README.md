tmux profile
------------

tmux-profile is a small script to quickly configure and initialize 
[tmux](http://tmux.sourceforge.net/) sessions.

A profile is YAML file which details sessions, windows, and panes and allows
shell commands and keystrokes to be sent to each.

Consider an example.yaml:

    description: An example profile.
    sessions:
        - name: example
          attach: true
          dir: /tmp/
          windows:
            - name: hello
              cmd: vim hello_world.rb
              send: g n
              panes:
                  - split: v
                    size: 10
                    cmd: git status
            - name: server
              cmd: ssh foo@bar 

If this file is stored within the profiles directory, then the profile can be
initialized like so:

ruby load-tmux-profile.rb example

Running this will create (and attach) a single tmux session named 'example', 
with 2 windows, the first of which will have 2 panes. One pane will open a file 
in vim, the other show the git status. The second window will ssh into server 
*bar* as user *foo*. 

Hopefully you can create more useful profiles without difficulty!


notes
-----

I find it useful to create an alias for this command on your shell, for quick
access. For example within a .bashrc file:

    alias ltp="ruby /path/to/load-tmux-profile.rb"

