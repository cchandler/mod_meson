-module(mod_meson).

-behaviour(gen_server).
-behaviour(gen_mod).

%-include("/Users/chris/Downloads/rabbitmq-erlang-client-60db1bd04676/include/amqp_client.hrl").
-include_lib("rabbit_erlang_client/include/amqp_client.hrl").
-include("/Users/chris/Projects/ejabberd_installed/lib/ejabberd/include/ejabberd.hrl").
-include("/Users/chris/Projects/ejabberd_installed/lib/ejabberd/include/jlib.hrl").

-include_lib("rabbitmq_server/include/rabbit.hrl").
-include_lib("rabbitmq_server/include/rabbit_framing.hrl").

%export for gen_mod
-export([start_link/2, start/2, stop/1]).
%export for gen_server
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).
%export for ejabberd routing
-export([route/3]).
%export to test things from erl

-record(state, {host}).

-define(PROCNAME, ejabberd_mod_meson).

start_link(Host,Opts) ->
	Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
	gen_server:start_link({local,Proc}, ?MODULE, [Host, Opts], []).

start(Host,Opts) ->
	Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
	ChildSpec =
		{Proc,
			{?MODULE, start_link, [Host, Opts]},
			temporary,
			1000,
			worker,
			[?MODULE]},
		supervisor:start_child(ejabberd_sup, ChildSpec).
		
stop(Host) ->
	Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
	gen_server:call(Proc,stop),
	supervisor:terminate_child(ejabberd_sup,Proc),
	supervisor:delete_child(ejabberd_sup, Proc).

init([Host,Opts]) -> 
	MyHost = gen_mod:get_opt_host(Host, Opts, "meson.@HOST@"),
	ejabberd_router:register_route(MyHost, {apply, ?MODULE, route}),
	%Create a process for handling AMQP messages
	Pid = spawn( fun loop/0 ),
	register(amqpSend, Pid),
	Pid2 = spawn( fun receive_from_amqp/0 ),
	Pid2 ! {start},
	register(amqpReceive, Pid2),
	?INFO_MSG("Initialized meson on ~p and registered route", [MyHost]),
    {ok, #state{host = MyHost}}.

handle_info({route, From, To, Packet}, State) ->
	{noreply, State};
handle_info(_Info, State) ->
	{noreply, State}.
	
route(From, To, Packet) ->
	{ExchangeName, Vhost} = jid_to_xname(To),
	Data = xml:get_subtag_cdata(Packet, "body"),
	BinaryData = list_to_binary([Data]),
	Pid = whereis(amqpSend),
	% Pid ! {send_to_amqp, Vhost, BinaryData}.
	Pid ! {send_to_amqp, <<"internal">>, BinaryData}.

terminate(Reason, State) -> ok.

handle_call(stop, _From, State) -> {stop, normal, ok, State}.

handle_cast(_Msg, State) -> {noreply, State}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

loop() ->
	send_to_amqp([],[]),
	ok.
	
send_to_amqp([], []) ->
	receive
		{send_to_amqp, Vhost, Payload} ->
			?INFO_MSG("Attempting to send message to vhost ~p with payload ~p", [Vhost,Payload]),
			Connection = amqp_connection:start("internal", "password", "localhost", <<"internal">>),
			Channel = lib_amqp:start_channel(Connection),
			Q = <<"find-goal">>,
			lib_amqp:declare_queue(Channel, Q),
			X = <<"find-goal">>,
			lib_amqp:declare_exchange(Channel, X),
			BindKey = <<"find-goal">>,
			lib_amqp:bind_queue(Channel, X, Q, BindKey),
			lib_amqp:publish(Channel, X, BindKey, Payload),
			%Tail recurse with the Connection and Channel
			send_to_amqp(Connection, Channel)
	end;
send_to_amqp(Connection,Channel) ->
	receive
		{send_to_amqp, Vhost, Payload} ->
			?INFO_MSG("Attempting to send message to vhost ~p with payload ~p", [Vhost,Payload]),
			Q = <<"find-goal">>,
			lib_amqp:declare_queue(Channel, Q),
			X = <<"find-goal">>,
			lib_amqp:declare_exchange(Channel, X),
			BindKey = <<"find-goal">>,
			lib_amqp:bind_queue(Channel, X, Q, BindKey),
			lib_amqp:publish(Channel, X, BindKey, Payload),
			send_to_amqp(Connection, Channel);
		{close} ->
			lib_amqp:teardown(Connection,Channel)
	end.

loop_receive() ->
	receive_from_amqp(),
	ok.
	
receive_from_amqp() ->
	receive
		{start} ->
			?INFO_MSG("Starting receive", []),
			{ok, Consumer} = gen_event:start_link(),
		    gen_event:add_handler(Consumer, mod_meson_consumer , [] ),
			Connection = amqp_connection:start("internal", "password", "localhost", <<"parrotlabs">>),
			Channel = lib_amqp:start_channel(Connection),
			Q = <<"xmpp_outbound">>,
			lib_amqp:subscribe(Channel, Q, Consumer, true),
			?INFO_MSG("Subscribing to queue ~p on vhost ~p", [Q, <<"internal">>]),
			receive_from_amqp()
	end.

jid_to_qname(#jid{luser = U, lserver =S}) ->
	list_to_binary(U ++ "@" ++ S).

jid_to_xname(#jid{luser = U, lresource = R}) ->
	{list_to_binary(U), list_to_binary(R)}.