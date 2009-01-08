%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is the RabbitMQ Erlang Client.
%%
%%   The Initial Developers of the Original Code are LShift Ltd.,
%%   Cohesive Financial Technologies LLC., and Rabbit Technologies Ltd.
%%
%%   Portions created by LShift Ltd., Cohesive Financial
%%   Technologies LLC., and Rabbit Technologies Ltd. are Copyright (C)
%%   2007 LShift Ltd., Cohesive Financial Technologies LLC., and Rabbit
%%   Technologies Ltd.;
%%
%%   All Rights Reserved.
%%
%%   Contributor(s): Ben Hood <0x6e6562@gmail.com>.
%%

-module(mod_meson_consumer).

-behaviour(gen_event).

-include("/Users/chris/Projects/ejabberd_installed/lib/ejabberd/include/ejabberd.hrl").
-include("/Users/chris/Projects/ejabberd_installed/lib/ejabberd/include/jlib.hrl").
-include("/Users/chris/Projects/meson_core/include/meson_core_records.hrl").

-include_lib("rabbitmq_server/include/rabbit_framing.hrl").
-include_lib("rfc4627/include/rfc4627.hrl").

-export([init/1, handle_info/2, terminate/2]).
-export([code_change/3, handle_call/2, handle_event/2]).

%---------------------------------------------------------------------------
% gen_event callbacks
%---------------------------------------------------------------------------

init(_Args) ->
	?INFO_MSG("Initialized a receiver", []),
    {ok, []}.

handle_call(_Request, State) ->
    {ok, not_understood, State}.

handle_event(_Event, State) ->
    {ok, State}.

handle_info(shutdown, State) ->
    ?INFO_MSG("AMQP Consumer SHUTDOWN~n", []),
    {remove_handler, State};

handle_info(#'basic.consume_ok'{consumer_tag = ConsumerTag}, State) ->
    ?INFO_MSG("AMQP Consumer, rec'd consume ok, tag= ~p~n", [ConsumerTag] ),
    {ok, State};

handle_info(#'basic.cancel_ok'{consumer_tag = ConsumerTag}, State) ->
    ?INFO_MSG("AMQP Consumer, rec'd cancel ok, tag= ~p~n", [ConsumerTag] ),
    {ok, State};

handle_info({#'basic.deliver'{},
              {content, _ClassId, _Properties, _PropertiesBin, Payload}},
              State) ->
     ?INFO_MSG("AMQP Consumer, rec'd: ~p~n", [ Payload ] ),
	 [P] = Payload,
	 DPayload = meson_message_to_goal(binary_to_list(P)),
	 % send_message(
	 % 		jlib:make_jid("noreply","chrischandler.name","sys"), 
	 % 		goal_to_jid(DPayload#meson_message.goal), "chat", DPayload#meson_message.body
	 % 		),
	From = jlib:make_jid("noreply","chrischandler.name","sys"), 
	?INFO_MSG("Value of JID: ~p~n", [DPayload#meson_message.jid]),
	 send_messages(From, DPayload#meson_message.jid, DPayload#meson_message.body),
     {ok, State}.


send_messages(From, [H|T], BodyStr) ->
	[{_ID, Username}, {_ID2, Domain}, {_ID3, Resource}] = H,
	To = jlib:make_jid( binary_to_list(Username), binary_to_list(Domain), binary_to_list(Resource) ),
	send_message(From, To, "chat", BodyStr),
	send_messages(From, T, BodyStr),
	ok;
send_messages(From, [], BodyStr)->
	ok;
send_messages(From, To, BodyStr) ->
	[{_ID, Username}, {_ID2, Domain}, {_ID3, Resource}] = To,
	ToUser = jlib:make_jid( binary_to_list(Username), binary_to_list(Domain), binary_to_list(Resource) ),
	send_message(From, ToUser, "chat", BodyStr).

send_message(From, To, TypeStr, BodyStr) ->
	    XmlBody = {xmlelement, "message",
		       [{"type", TypeStr},
			{"from", jlib:jid_to_string(From)},
			{"to", jlib:jid_to_string(To)}],
		       [{xmlelement, "body", [],
			 [{xmlcdata, BodyStr}]}]},
	    ?INFO_MSG("Delivering ~p -> ~p~n~p", [From, To, XmlBody]),
	    ejabberd_router:route(From, To, XmlBody).
     
terminate(_Args, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

	%% Copy paste start

	meson_message_to_goal(A) ->
		S = mochijson2:decode(A),
		Input = #meson_message{},
		parse_message(S, Input).

	parse_message({json, A}, Input) ->
			parse_message(A, Input);	
	parse_message({struct, A}, Input) ->
		parse_message(A, Input);
	parse_message({C,D}, Input) when is_binary(C) and is_binary(D) ->
		case C of 
			<<"message">> ->
				Input#meson_message{body=D};
			<<"goal">> ->
				Input#meson_message{goal=D};
			_ ->
				%Ignore unknowns
				Input
		end;
	parse_message({C,D}, Input) when is_binary(C) and is_list(D) ->
		[{struct, E}] = D,
		case C of
			<<"jidlist">> ->
				Input#meson_message{jid=E}
			end;
	parse_message([H|T], Input) ->
		Intermediate = parse_message(H, Input),
		parse_message(T, Intermediate);
	parse_message([], Input) ->
		Input.
		
		
		%%% Copy Paste END 
	
% goal_to_jid(Input) ->
% 	case Input of
% 		"9acae331ef809378a2989be1872132ce" -> jlib:make_jid("jack","chrischandler.name", "");
% 		"912ec803b2ce49e4a541068d495ab570" -> jlib:make_jid("jack", "chrischandler.name", "");
% 		<<"e1dfd697686142602e1930803a2229b5">> -> jlib:make_jid("jack", "chrischandler.name", "");
% 		true -> jlib:make_jid("jack","chrischandler.name", "/Blast")
% 	end.