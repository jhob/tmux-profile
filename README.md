tmux profile
------------

tmux-profile is a small script to quickly configure and initialize
[tmux](http://tmux.github.io/) sessions.


Installation
------------

Install tmux-profile somewhere

    git clone git@github.com:jhob/tmux-profile.git

Create a `~/.tmux-profiles` directory for your custom profiles.

    mkdir ~/.tmux-profiles

To make it convenient, alias the `load-tmux-profile.rb` script. E.g. append the following to your `~/.bashrc`:

    alias ltp="ruby /path/to/tmux-profile/load-tmux-profile.rb"


Usage
-----

List all profiles:

    ltp -l

Load example profile:

    ltp example


Example
-------

A profile is YAML file which details sessions, windows, and panes and allows
shell commands and keystrokes to be sent to each.

Consider an example.yaml:

    description: An example profile.
    sessions:
      - name: example
        attach: true
        dir: /tmp/
        windows:
          - *editor
          - name: staging
            cmd: ssh foo@staging-server-1
            panes:
              - split: horizontal
                cmd: ssh foo@staging-server-2
          - name: production
            cmd: ssh bar@production-server-1
            panes:
              - split: horizontal
                cmd: ssh bar@production-server-2

If this file is stored within your `~/.tmux-profiles` directory, then the profile can be
initialized like so:

    ruby load-tmux-profile.rb example

Running this will create (and attach) a single tmux session named 'example',
with 3 windows:

1. the first of which will have 3 panes. One pane will open a file
   in vim, the other two show `git status` and `git log`. This is referencing a
   helper named `editor`.
2. The second window will have two splits, each `ssh`'ing into different
   machines.
3. The third is much like the second, but into different machines again.

Hopefully you can create more useful profiles without difficulty!


TODO
----

- Make script runnable from within a tmux client without trying to nest. Switch
  into loaded profile.
