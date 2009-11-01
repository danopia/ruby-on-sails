Ruby on Sails - Sailing the Waves of Google with Ruby!
=============

(aka: Google Wave provider, implemented in Ruby, with a Ruby on Rails interface)

### Basics
Ruby on Sails isn't really set up for sidespread setups (or even sending to a
friend). You'll notice the wave.danopia.net folder, this is the rails app. The
main provider file, xmpp_component.rb, requires a file from the rails site, so
you'll have to update the paths if you move stuff around.


Setup
-----
It's easiest to use Sails when you already have a XMPP server that Fedone can
connect to. To set up Openfire, follow [these directions][g_install].

### Certificates
Sails also [attempts to] sign deltas, so you'll need to create certs for it to
use. It uses "#{domain}.cert" and "#{domain}.key", which is what is given to
you if you follow [Google's instructions][g_certs] to create certs. (I have
included their make-cert.sh utility in the Sails repo.)

### Dependancies
You'll need a few gems to run Sails and the provided WebUI, so make sure that
you have RubyGems (and ruby!) installed, and install 'authlogic', 'rails',
and 'sqlite'. You may want to consult `gem list --local` for a list of
installed gems. The sqlite gem probably will want you to install developement
headers/packages for sqlite; on my Ubuntu machine, the dev package is called
'libsqlite3-dev'.

### Configoration
Finally, you'll have to config the XMPP component. Ruby on Sails will try
reading sails.conf, a YAML file, for configuration settings. You'll find XMPP
name, host, port, password, and service name there, plus a few other worthless
things.


Running
-------

### Running the backend
Make sure that you have OpenFire (or some other XMPP server) configed and
_running_. Run the XMPP component like so:

		ruby xmpp_component.rb

If it has some file reading error, then it can't find the certs (TODO: cleaner
error message). If it said the server denied the component, ensure that you
configged your XMPP server correctly (and if you've used FedOne, that it isn't
running). If anything else happened, either it's good (it didn't crash) or it's
bad (gist the output and file a bug report).

### Running the WebUI
The Sails WebUI is built with Ruby on Rails. The Ruby on Sails name is also
stolen from Rails' name. First things first, you need a DB to store user
accounts in. `cd` to wave.danopia.net/ and run `rake db:migrate`. If anything
other than success occurs, scroll down to the Contact Me section.

The easiest way to run the site in a dev environment is by `cd`ing to
wave.danopia.net/ and running:

		./script/server

...which should start up a cute little HTTP server, ready for browsing on port
3000. Visit the site. You'll have to register an account - your DB is going to
be a fresh creation, not a copy of the live one from my site. Once that's set
up and running, DRb-error-free, play around in the webui for a bit :P


Contributing
------------
1. *Fork it*.
2. Create a branch
3. Commit your changes
4. Push to the branch
5. Send me a link to your branch (see the "Contact me" section)
6. Enjoy a refreshing glass of water and wait


Contact me
----------
I idle in #googlewave on FreeNode 24/7 and also on my private network at
irc.eighthbit.net. You can send me GitHub messages or email me at
me.github@danopia.net. I also may read any waves sent to me (my username is
ddanopia).


[g_install]: http://code.google.com/p/wave-protocol/wiki/Installation
[g_certs]: http://code.google.com/p/wave-protocol/wiki/Certificates
