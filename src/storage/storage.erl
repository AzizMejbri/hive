-module(storage).

%% Users
-export([create_user/4, create_admin/4, get_user/1, get_user_by_name/1,
         get_user_by_email/1, list_users/0, update_last_connected/1, delete_user/1,
         verify_password/2]).
%% Channels
-export([create_channel/2, get_channel/1, get_channel_by_name/1, list_channels/0,
         delete_channel/2]).
%% Subscriptions
-export([subscribe/2, unsubscribe/2, is_subscribed/2, list_subscriptions/1,
         list_subscribers/1]).
%% Friendships
-export([befriend/2, unfriend/2, are_friends/2, list_friends/1]).
%% Messages
-export([post_message/3, get_message/1, edit_message/2, delete_message/1, messages_in/2,
         messages_before/3, message_count/1]).

-include("hive.hrl").

%%====================================================================
%% Users
%%====================================================================

-spec create_user(Name, Email, Gender, Password) -> {ok, User} | {error, Reason}
  when Name :: binary(),
       Email :: binary(),
       Gender :: gender(),
       Password :: binary(),
       User :: user(),
       Reason :: atom().
create_user(Name, Email, Gender, Password) ->
  txn(fun() ->
         %% ensure only one user has this email
         case mnesia:read(user, Email) of
           [] ->
             %% ensure only one user has this email
             case mnesia:read(user, Name) of
               [] ->
                 %% create Hash for password and write User
                 case create_password(Password) of
                   {ok, HashedPass} ->
                     User =
                       #user{id = new_id(),
                             name = Name,
                             email = Email,
                             gender = Gender,
                             password = HashedPass,
                             created_at = now_ms(),
                             last_connected = undefined,
                             privilege = user},
                     ok = mnesia:write(User),
                     {ok, User};
                   {error, Reason} ->
                     logger:log(error,
                                "Failed to hash the password for the user ~p ... Reason: ~p",
                                [Name, Reason]),
                     {error, Reason}
                 end;
               [_] ->
                 logger:log(error, "User already exists with this name: ~p", [Name]),
                 {error, name_already_exists}
             end;
           [_] ->
             logger:log(error, "User already exists with this email: ~p", [Email]),
             {error, email_already_exsits}
         end
      end).

-spec create_admin(Name, Email, Gender, Password) -> {ok, User} | {error, Reason}
  when Name :: binary(),
       Email :: binary(),
       Gender :: gender(),
       Password :: binary(),
       User :: user(),
       Reason :: atom().
create_admin(Name, Email, Gender, Password) ->
  txn(fun() ->
         %% ensure only one user has this email
         case mnesia:read(user, Email) of
           [] ->
             %% ensure only one user has this email
             case mnesia:read(user, Name) of
               [] ->
                 %% create Hash for password and write User
                 case create_password(Password) of
                   {ok, HashedPass} ->
                     User =
                       #user{id = new_id(),
                             name = Name,
                             email = Email,
                             gender = Gender,
                             password = HashedPass,
                             created_at = now_ms(),
                             last_connected = undefined,
                             privilege = admin},
                     ok = mnesia:write(User),
                     {ok, User};
                   {error, Reason} ->
                     logger:log(error,
                                "Failed to hash the password for the user ~p ... Reason: ~p",
                                [Name, Reason])
                 end;
               [_] ->
                 logger:log(error, "User already exists with this name: ~p", [Name]),
                 {error, email_already_exsits}
             end;
           [_] ->
             logger:log(error, "User already exists with this email: ~p", [Email]),
             {error, email_already_exsits}
         end
      end).

-spec get_user(Id) -> {ok, User} | {error, Reason}
  when Id :: user_id(),
       User :: user(),
       Reason :: atom().
get_user(Id) ->
  txn(fun() ->
         case mnesia:read(user, Id) of
           [U] -> {ok, U};
           [] -> {error, not_found}
         end
      end).

-spec get_user_by_name(Name) -> {ok, User} | {error, Reason}
  when Name :: binary(),
       User :: user(),
       Reason :: atom().
get_user_by_name(Name) ->
  txn(fun() ->
         case mnesia:match_object(#user{id = '_',
                                        name = Name,
                                        _ = '_'})
         of
           [] -> {error, user_not_found};
           [U] -> {ok, U}
         end
      end).

-spec list_users() -> {ok, [user()]}.
list_users() ->
  txn(fun() -> {ok, mnesia:match_object(#user{_ = '_'})} end).

-spec update_last_connected(Id) -> {ok, User} | {error, Reason}
  when Id :: user_id(),
       User :: user(),
       Reason :: atom().
update_last_connected(Id) ->
  txn(fun() ->
         case mnesia:read(user, Id) of
           [U] ->
             NewU = U#user{last_connected = now_ms()},
             ok = mnesia:write(NewU),
             {ok, NewU};
           [] -> {error, not_found}
         end
      end).

-spec delete_user(user_id()) -> {ok, deleted} | {error, not_found}.
delete_user(Id) ->
  txn(fun() ->
         case mnesia:read(user, Id) of
           [_] ->
             ok = mnesia:delete({user, Id}),
             {ok, deleted};
           [] -> {error, not_found}
         end
      end).

-spec get_user_by_email(Email) -> {ok, User} | {error, Reason}
  when Email :: binary(),
       User :: user(),
       Reason :: term().
get_user_by_email(Email) ->
  txn(fun(_) ->
         case mnesia:match_object(#user{id = '_',
                                        email = Email,
                                        _ = '_'})
         of
           [] -> {error, user_not_found};
           [U] -> {ok, U}
         end
      end).

-spec create_password(Password) -> {ok, HashedPass} | {error, atom()}
  when Password :: binary(),
       HashedPass :: binary().
create_password(Password) ->
  %% 1. Generate a fresh 16-byte random salt
  Salt = crypto:strong_rand_bytes(16),

  %% 2. Define your Argon2id parameters
  Algorithm = argon2id,
  TimeCost = 3,        % Iterations (t)
  MemoryCost = 65536,    % Memory in KiB (65536 KiB = 64 MiB)
  Parallelism = 1,        % Lanes (p)
  HashLen = 32,       % Output hash length in bytes

  case jargon:hash(Password, Salt, Algorithm, TimeCost, MemoryCost, Parallelism, HashLen) of
    {ok, _RawHash, EncodedHash} ->
      {ok, EncodedHash};
    {error, Reason} ->
      {error, Reason}
  end.

-spec verify_password(Name, CandidatePassword) -> {ok, User} | {error, Reason}
  when Name :: binary(),
       CandidatePassword :: binary(),
       User :: user(),
       Reason :: atom().
verify_password(Name, CandidatePassword) ->
  txn(fun() ->
         case get_user_by_name(Name) of
           {ok, U} ->
             StoredEncodedHash = U#user.password,
             case jargon:verify(StoredEncodedHash, CandidatePassword) of
               {error, Reason} -> {error, Reason};
               {ok, true} -> {ok, U#user{password = hidden}};
               {ok, false} -> {error, invalid_credentials}
             end;
           {error, _Reason} -> {error, invalid_credentials}
         end
      end).

                % Password matches

%%====================================================================
%% Channels
%%====================================================================

-spec create_channel(Name, Creator) -> {ok, Channel} | {error, Reason}
  when Name :: binary(),
       Creator :: user_id(),
       Channel :: channel(),
       Reason :: {already_exists, {channel, name, binary()}} | term().
create_channel(Name, Creator) ->
  txn(fun() ->
         case find_channels_by_name(Name) of
           {ok, [_ | _]} -> {error, {already_exists, {channel, name, Name}}};
           {ok, []} ->
             Ch =
               #channel{id = new_id(),
                        name = Name,
                        created_at = now_ms(),
                        admin = Creator},
             ok = mnesia:write(Ch),
             {ok, Ch}
         end
      end).

-spec get_channel(Id) -> {ok, Channel} | {error, Reason}
  when Id :: channel_id(),
       Channel :: channel(),
       Reason :: not_found | term().
get_channel(Id) ->
  txn(fun() ->
         case mnesia:read(channel, Id) of
           [C] -> {ok, C};
           [] -> {error, not_found}
         end
      end).

-spec get_channel_by_name(Name) -> {ok, Channel} | {error, Reason}
  when Name :: binary(),
       Channel :: channel(),
       Reason :: not_found | term().
get_channel_by_name(Name) ->
  txn(fun() ->
         case find_channels_by_name(Name) of
           {ok, [C | _]} -> {ok, C};
           {ok, []} -> {error, not_found}
         end
      end).

-spec list_channels() -> {ok, [channel()]}.
list_channels() ->
  txn(fun() -> {ok, mnesia:match_object(#channel{_ = '_'})} end).

-spec delete_channel(Id, AdminId) -> {ok, deleted} | {error, Reason}
  when Id :: channel_id(),
       AdminId :: user_id(),
       Reason :: not_found | term().
delete_channel(Id, AdminId) ->
  txn(fun() ->
         case mnesia:read(channel, Id) of
           [Ch] ->
             if Ch#channel.admin == AdminId ->
                  ok = mnesia:delete({channel, Id}),
                  {ok, deleted};
                true -> {error, forbidden}
             end;
           [] -> {error, not_found}
         end
      end).

-spec find_channels_by_name(binary()) -> {ok, [channel()]}.
find_channels_by_name(Name) ->
  {ok, mnesia:read(channel, Name)}.

%%====================================================================
%% Subscriptions
%%====================================================================

-spec subscribe(UserId, ChannelId) -> {ok, Key} | {error, Reason}
  when UserId :: user_id(),
       ChannelId :: channel_id(),
       Key :: {user_id(), channel_id()},
       Reason :: already_subscribed | term().
subscribe(UserId, ChannelId) ->
  txn(fun() ->
         Key = {UserId, ChannelId},
         case mnesia:read(subscription, Key) of
           [_] -> {error, already_subscribed};
           [] ->
             ok = mnesia:write(#subscription{key = Key, subscribed_at = now_ms()}),
             {ok, Key}
         end
      end).

-spec unsubscribe(UserId, ChannelId) -> {ok, deleted} | {error, Reason}
  when UserId :: user_id(),
       ChannelId :: channel_id(),
       Reason :: not_found | term().
unsubscribe(UserId, ChannelId) ->
  txn(fun() ->
         Key = {UserId, ChannelId},
         case mnesia:read(subscription, Key) of
           [_] ->
             ok = mnesia:delete({subscription, Key}),
             {ok, deleted};
           [] -> {error, not_found}
         end
      end).

-spec is_subscribed(UserId, ChannelId) -> {ok, boolean()} | {error, term()}
  when UserId :: user_id(),
       ChannelId :: channel_id().
is_subscribed(UserId, ChannelId) ->
  txn(fun() ->
         case mnesia:read(subscription, {UserId, ChannelId}) of
           [_] -> {ok, true};
           [] -> {ok, false}
         end
      end).

-spec list_subscriptions(UserId) -> {ok, [{ChannelId, timestamp()}]}
  when UserId :: user_id(),
       ChannelId :: channel_id().
list_subscriptions(UserId) ->
  txn(fun() ->
         Subs =
           mnesia:foldl(fun(#subscription{key = {U, C}, subscribed_at = T}, Acc) ->
                           if U == UserId -> [{C, T} | Acc];
                              true -> Acc
                           end
                        end,
                        [],
                        subscription),
         {ok, Subs}
      end).

-spec list_subscribers(ChannelId) -> {ok, [{UserId, timestamp()}]}
  when ChannelId :: channel_id(),
       UserId :: user_id().
list_subscribers(ChannelId) ->
  txn(fun() ->
         Users =
           mnesia:foldl(fun(#subscription{key = {U, C}, subscribed_at = T}, Acc) ->
                           if C == ChannelId -> [{U, T} | Acc];
                              true -> Acc
                           end
                        end,
                        [],
                        subscription),
         {ok, Users}
      end).

%%====================================================================
%% Friendships
%%====================================================================

-spec befriend(UserA, UserB) -> {ok, Friendship} | {error, Reason}
  when UserA :: user_id(),
       UserB :: user_id(),
       Friendship :: friendship(),
       Reason :: already_friends | cannot_friend_self | term().
befriend(UserA, UserB) when UserA =/= UserB ->
  {Min, Max} = {min(UserA, UserB), max(UserA, UserB)},
  txn(fun() ->
         case mnesia:read(friendship, {Min, Max}) of
           [_] -> {error, already_friends};
           [] ->
             F = #friendship{key = {Min, Max}, friends_since = now_ms()},
             ok = mnesia:write(F),
             {ok, F}
         end
      end);
befriend(_, _) ->
  {error, cannot_friend_self}.

-spec unfriend(UserA, UserB) -> {ok, deleted} | {error, Reason}
  when UserA :: user_id(),
       UserB :: user_id(),
       Reason :: not_found | term().
unfriend(UserA, UserB) ->
  {Min, Max} = {min(UserA, UserB), max(UserA, UserB)},
  txn(fun() ->
         case mnesia:read(friendship, {Min, Max}) of
           [_] ->
             ok = mnesia:delete({friendship, {Min, Max}}),
             {ok, deleted};
           [] -> {error, not_found}
         end
      end).

-spec are_friends(UserA, UserB) -> {ok, boolean()} | {error, term()}
  when UserA :: user_id(),
       UserB :: user_id().
are_friends(UserA, UserB) ->
  {Min, Max} = {min(UserA, UserB), max(UserA, UserB)},
  txn(fun() ->
         case mnesia:read(friendship, {Min, Max}) of
           [_] -> {ok, true};
           [] -> {ok, false}
         end
      end).

-spec list_friends(UserId) -> {ok, [{UserId, timestamp()}]} when UserId :: user_id().
list_friends(UserId) ->
  txn(fun() ->
         Friends =
           mnesia:foldl(fun(#friendship{key = {A, B}, friends_since = S}, Acc) ->
                           if UserId == A -> [{B, S} | Acc];
                              UserId == B -> [{A, S} | Acc];
                              true -> Acc
                           end
                        end,
                        [],
                        friendship),
         {ok, Friends}
      end).

%%====================================================================
%% Messages
%%====================================================================

-spec post_message(Sender, Target, Content) -> {ok, Message} | {error, term()}
  when Sender :: user_id(),
       Target :: {channel, channel_id()} | {dm, user_id()},
       Content :: binary(),
       Message :: message().
post_message(Sender, Target, Content) ->
  txn(fun() ->
         N = new_id(),
         Msg =
           #message{id = N,
                    sender = Sender,
                    target = Target,
                    seq = N,
                    content = Content,
                    sent_at = now_ms(),
                    last_edited = now_ms(),
                    deleted_for_everyone = false,
                    edited = false},
         ok = mnesia:write(Msg),
         {ok, Msg}
      end).

-spec get_message(Id) -> {ok, Message} | {error, Reason}
  when Id :: message_id(),
       Message :: message(),
       Reason :: not_found | term().
get_message(Id) ->
  txn(fun() ->
         case mnesia:read(message, Id) of
           [M] -> {ok, M};
           [] -> {error, not_found}
         end
      end).

-spec edit_message(Id, NewContent) -> {ok, Message} | {error, Reason}
  when Id :: message_id(),
       NewContent :: binary(),
       Message :: message(),
       Reason :: not_found | term().
edit_message(Id, NewContent) ->
  txn(fun() ->
         case mnesia:read(message, Id) of
           [M] ->
             Updated =
               M#message{content = NewContent,
                         edited = true,
                         last_edited = now_ms()},
             ok = mnesia:write(Updated),
             {ok, Updated};
           [] -> {error, not_found}
         end
      end).

-spec delete_message(Id) -> {ok, Message} | {error, Reason}
  when Id :: message_id(),
       Message :: message(),
       Reason :: not_found | term().
delete_message(Id) ->
  txn(fun() ->
         case mnesia:read(message, Id) of
           [M] ->
             Updated = M#message{deleted_for_everyone = true},
             ok = mnesia:write(Updated),
             {ok, Updated};
           [] -> {error, not_found}
         end
      end).

-spec messages_in(Target, Limit) -> {ok, [message()]} | {error, term()}
  when Target :: {channel, channel_id()} | {dm, user_id()},
       Limit :: pos_integer().
messages_in(Target, Limit) when is_integer(Limit), Limit > 0 ->
  txn(fun() ->
         All = live_messages(Target),
         Sorted =
           lists:reverse(
             lists:keysort(#message.seq, All)),
         {ok, lists:sublist(Sorted, Limit)}
      end).

-spec messages_before(Target, BeforeSeq, Limit) -> {ok, [message()]} | {error, term()}
  when Target :: {channel, channel_id()} | {dm, user_id()},
       BeforeSeq :: non_neg_integer(),
       Limit :: pos_integer().
messages_before(Target, BeforeSeq, Limit) when is_integer(Limit), Limit > 0 ->
  txn(fun() ->
         All = live_messages(Target),
         Older = [M || M <- All, M#message.seq < BeforeSeq],
         Sorted =
           lists:reverse(
             lists:keysort(#message.seq, Older)),
         {ok, lists:sublist(Sorted, Limit)}
      end).

-spec message_count(Target) -> {ok, non_neg_integer()} | {error, term()}
  when Target :: {channel, channel_id()} | {dm, user_id()}.
message_count(Target) ->
  txn(fun() -> {ok, length(live_messages(Target))} end).

-spec live_messages(Target) -> [message()]
  when Target :: {channel, channel_id()} | {dm, user_id()}.
live_messages(Target) ->
  Ms = mnesia:index_read(message, Target, #message.target),
  [M || M <- Ms, not M#message.deleted_for_everyone].

%%====================================================================
%% Helpers
%%====================================================================

-spec txn(Fun) -> Result when Fun :: fun(() -> Result).
txn(Fun) ->
  case mnesia:transaction(Fun) of
    {atomic, Result} ->
      Result;
    {aborted, Reason} ->
      {error, Reason}
  end.

-spec now_ms() -> timestamp().
now_ms() ->
  erlang:system_time(millisecond).

-spec new_id() -> pos_integer().
new_id() ->
  erlang:unique_integer([positive, monotonic]).
