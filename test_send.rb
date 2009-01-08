#!/opt/local/bin/ruby

#
# This is my handy-dandy test sending script to send an XMPP message to ejabberd
#

require 'rubygems'
require 'xmpp4r'
require 'json'
require 'digest'

jid = Jabber::JID.new("chris@chrischandler.name")
client = Jabber::Client.new(jid)
client.connect
client.auth("password")

client.send(Jabber::Presence.new.set_status("available"))

md5 = Digest::MD5.new
# goal = md5.update("I roxor")
# goal = md5.update("asdf")
goal = "f944460a582be8287e72ae9c85e7d5ad"
# goal = "7503affc8f8976d1fa3d23950cd4a2b4"


m = Jabber::Message.new("blue@meson.chrischandler.name/parrotlabs", 
  {:goal => goal.to_s, :message => "Encoded message in JSON format "}.to_json )

client.send(m)