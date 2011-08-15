This is IRCSH, a pure[1] bash IRC bot framework, targeted at simple
hacks of bots that don't need to be written in something
faster/saner/better.

Basically everything is overridable by the configuration file, which
is sourced immediately prior to connection. With no configuration
beyond the user/nick/realname, the bot will connect to the server,
respond to PINGs, and log everything else it sees to the
terminal. With a few quick lines of shell, it can be made to respond
to private and channel messages, or whatever else you want your bot to
do. It's just a shell script! See config.sh.sample for a simple
"hello bot" that shows the important configuration options and callbacks,
see the source for the rest.

IRCSH has very few external dependencies besides a modern Bash (as old
as 4.1.5 is known to work). It doesn't shell out to anything, sed, tr,
etc, except for netcat (any version will do) to do network I/O. This
could be easily replaced with /dev/tcp if you have a Bash that supports
networking.
