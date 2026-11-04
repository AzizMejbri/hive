-module(command).

-include("hive.hrl").

-export([send/2, send/3, handle/2]).

-type conn_state() :: #{socket := inet:socket(), user := user() | undefined}.
-type csr() ::
  {ok, conn_state()} |
  {error, closed | {timeout, binary() | erlang:iovec()} | inet:posix()}.
-type mapper() :: fun((conn_state()) -> conn_state()).

%%====================================================================
%% send
%%====================================================================

-spec send(conn_state(), term(), mapper()) -> csr().
send(#{socket := Socket, user := User} = State, Data, F) ->
  case gen_tcp:send(Socket, term_to_binary(Data)) of
    ok ->
      {ok, F(State)};
    {error, Reason} ->
      logger:log(warning,
                 "send failed: data=~p socket=~p user=~p reason=~p",
                 [Data, Socket, User, Reason]),
      {error, Reason}
  end.

-spec send(conn_state(), term()) -> csr().
send(State, Data) ->
  send(State, Data, fun(S) -> S end).

%%====================================================================
%% helpers
%%====================================================================

%% Strip the password hash before a user record crosses the wire.
-spec hide(user()) -> user().
hide(U) ->
  U#user{password = hidden}.

%%====================================================================
%% handle/2
%%====================================================================
-spec handle(term(), conn_state()) -> csr().
%% ---- Unauthenticated: only login is valid --------------------------
handle({signup, Name, Email, Gender, Password}, #{user := undefined} = State) ->
  case storage:create_user(Name, Email, Gender, Password) of 
    {ok, User} -> send(State, {ok, {user, hide(User)}});
    {error, Reason} -> send(State, {error, Reason})
  end;
  
handle({login, Name, Password}, #{user := undefined} = State) ->
  case storage:verify_password(Name, Password) of
    {ok, U} ->
      Hidden = hide(U),
      send(State, {ok, {user, Hidden}}, fun(S) -> S#{user := Hidden} end);
    {error, _} ->
      %% collapse every failure mode (bad pass, missing user, storage
      %% error) into a single reason to avoid user enumeration.
      send(State, {error, bad_credentials})
  end;
%% ---- Duplicate login ----------------------------------------------
handle({login, _, _}, #{user := U} = State) when U =/= undefined ->
  send(State, {error, already_logged_in});
%% ---- Everything else, unauthenticated -----------------------------
handle(_Command, #{user := undefined} = State) ->
  send(State, {error, not_authenticated});
%%====================================================================
%% Users (authenticated)
%%====================================================================
handle({logout}, #{user := U} = State) ->
  case storage:update_last_connected(U#user.id) of
    {ok, _} ->
      send(State, {ok, logged_out}, fun(S) -> S#{user := undefined} end);
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({me}, #{user := U} = State) ->
  send(State, {ok, {user, hide(U)}});
handle({get_user, Id}, State) ->
  case storage:get_user(Id) of
    {ok, U} ->
      send(State, {ok, {user, hide(U)}});
    {error, _} ->
      send(State, {error, not_found})
  end;
handle({get_user_by_name, Name}, State) ->
  case storage:get_user_by_name(Name) of
    {ok, U} ->
      send(State, {ok, hide(U)});
    {error, _} ->
      send(State, {error, not_found})
  end;
handle({list_users}, #{user := #user{privilege = admin}} = State) ->
  case storage:list_users() of
    {ok, Users} ->
      send(State, {ok, {users, [hide(U) || U <- Users]}});
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({list_users}, State) ->
  send(State, {error, forbidden});
handle({update_last_connected}, #{user := U} = State) ->
  case storage:update_last_connected(U#user.id) of
    {ok, NewU} ->
      send(State, {ok, {user, hide(NewU)}}, fun(S) -> S#{user := NewU} end);
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
%%====================================================================
%% Channels
%%====================================================================
handle({create_channel, Name}, #{user := #user{id = AdminId}} = State)
  when is_binary(Name) ->
  case storage:create_channel(Name, AdminId) of
    {ok, Ch} ->
      send(State, {ok, {channel, Ch}});
    {error, {already_exists, _}} = E ->
      send(State, E);
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({create_channel, _}, State) ->
  send(State, {error, invalid_args});
handle({get_channel, ChId}, State) ->
  case storage:get_channel(ChId) of
    {ok, Ch} ->
      send(State, {ok, {channel, Ch}});
    {error, _} ->
      send(State, {error, not_found})
  end;
handle({get_channel_by_name, Name}, State) ->
  case storage:get_channel_by_name(Name) of
    {ok, Ch} ->
      send(State, {ok, {channel, Ch}});
    {error, _} ->
      send(State, {error, not_found})
  end;
handle({list_channels}, #{user := #user{privilege = admin}} = State) ->
  case storage:list_channels() of
    {ok, Chs} ->
      send(State, {ok, {channels, Chs}});
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({delete_channel, ChId}, #{user := #user{id = AdminId}} = State) ->
  case storage:delete_channel(ChId, AdminId) of
    {ok, deleted} ->
      send(State, {ok, deleted});
    {error, _} ->
      send(State, {error, not_found})
  end;
%%====================================================================
%% Subscriptions
%%====================================================================
handle({subscribe, ChId}, #{user := U} = State) ->
  case storage:subscribe(U#user.id, ChId) of
    {ok, _} ->
      send(State, {ok, subscribed});
    {error, already_subscribed} = E ->
      send(State, E);
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({unsubscribe, ChId}, #{user := U} = State) ->
  case storage:unsubscribe(U#user.id, ChId) of
    {ok, _} ->
      send(State, {ok, unsubscribed});
    {error, _} ->
      send(State, {error, not_found})
  end;
handle({list_subscriptions}, #{user := U} = State) ->
  case storage:list_subscriptions(U#user.id) of
    {ok, Subs} ->
      Ids = [C || {C, _T} <- Subs],
      send(State, {ok, {subscriptions, Ids}});
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({list_subscribers, ChId}, State) ->
  case storage:list_subscribers(ChId) of
    {ok, Subs} ->
      Ids = [UId || {UId, _T} <- Subs],
      send(State, {ok, {subscribers, Ids}});
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
%%====================================================================
%% Messages
%%====================================================================
handle({post, {Type, _} = Target, Text}, #{user := #user{id = MyId}} = State)
  when Type =:= channel orelse Type =:= dm, is_binary(Text) ->
  case storage:post_message(MyId, Target, Text) of
    {ok, #message{id = MsgId, seq = Seq}} ->
      send(State, {ok, {posted, MsgId, Seq}});
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({post, _, _}, State) ->
  send(State, {error, invalid_args});
handle({get_message, MsgId}, State) ->
  case storage:get_message(MsgId) of
    {ok, M} ->
      send(State, {ok, {message, M}});
    {error, _} ->
      send(State, {error, not_found})
  end;
handle({get, {Type, _} = Target, Limit}, State)
  when Type =:= channel orelse Type =:= dm, is_integer(Limit), Limit > 0 ->
  case storage:messages_in(Target, Limit) of
    {ok, Msgs} ->
      send(State, {ok, {messages, Msgs}});
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({get, {Type, _} = Target, BeforeSeq, Limit}, State)
  when Type =:= channel orelse Type =:= dm, is_integer(BeforeSeq), BeforeSeq >= 0,
       is_integer(Limit), Limit > 0 ->
  case storage:messages_before(Target, BeforeSeq, Limit) of
    {ok, Msgs} ->
      send(State, {ok, {messages, Msgs}});
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({get, _, _}, State) ->
  send(State, {error, invalid_args});
handle({get, _, _, _}, State) ->
  send(State, {error, invalid_args});
handle({edit, MsgId, NewText}, #{user := #user{id = MyId}} = State)
  when is_binary(NewText) ->
  case storage:get_message(MsgId) of
    {ok, #message{sender = Id}} when Id == MyId ->
      case storage:edit_message(MsgId, NewText) of
        {ok, _} ->
          send(State, {ok, {edited, MsgId}});
        {error, R} ->
          send(State, {error, {internal, R}})
      end;
    {ok, _} ->
      send(State, {error, forbidden});
    {error, _} ->
      send(State, {error, not_found})
  end;
handle({edit, _, _}, State) ->
  send(State, {error, invalid_args});
handle({delete, MsgId}, #{user := #user{id = MyId}} = State) ->
  case storage:get_message(MsgId) of
    {ok, #message{sender = Id}} when Id == MyId ->
      case storage:delete_message(MsgId) of
        {ok, _} ->
          send(State, {ok, deleted});
        {error, R} ->
          send(State, {error, {internal, R}})
      end;
    {ok, _} ->
      send(State, {error, forbidden});
    {error, _} ->
      send(State, {error, not_found})
  end;
%%====================================================================
%% Friendships
%%====================================================================
handle({befriend, UserId}, #{user := U} = State) ->
  case storage:befriend(U#user.id, UserId) of
    {ok, F} ->
      send(State, {ok, {friendship, F}});
    {error, already_friends} = E ->
      send(State, E);
    {error, cannot_friend_self} = E ->
      send(State, E);
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({unfriend, UserId}, #{user := U} = State) ->
  case storage:unfriend(U#user.id, UserId) of
    {ok, _} ->
      send(State, {ok, unfriended});
    {error, _} ->
      send(State, {error, not_found})
  end;
handle({list_friends}, #{user := U} = State) ->
  case storage:list_friends(U#user.id) of
    {ok, Fs} ->
      Ids = [FId || {FId, _T} <- Fs],
      send(State, {ok, {friends, Ids}});
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
handle({are_friends, UserId}, #{user := U} = State) ->
  case storage:are_friends(U#user.id, UserId) of
    {ok, Bool} ->
      send(State, {ok, {boolean, Bool}});
    {error, R} ->
      send(State, {error, {internal, R}})
  end;
%%====================================================================
%% Catch-all (authenticated, unknown)
%%====================================================================
handle(Other, State) ->
  send(State, {error, {unknown_command, Other}}).
