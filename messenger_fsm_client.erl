-module(messenger_fsm_client).
-behaviour(gen_fsm).
-export([start/1, start_link/1, can_join/2, write/2, accept/1, decline/1, end_converse/1]). %% public API
-export([init/1, idle/2, idle_wait/2, texting/2, ask_wait/2, handle_sync_event/4, handle_event/3, handle_info/3]). %% states fsm

-record(state, {name="", supervisor_pid, monitor}).

% Client API

can_join(FsmPid, SupPid) ->
    gen_fsm:send_event(FsmPid, {can_join, SupPid, self()}).

write(FsmPid, Message) ->
    gen_fsm:send_event(FsmPid, {write, Message}).

accept(FsmPid) ->
    gen_fsm:send_event(FsmPid, accept).

decline(FsmPid) ->
    gen_fsm:send_event(FsmPid, decline).

end_converse(FsmPid) ->
    gen_fsm:send_event(FsmPid, end_converse).

%% fsm - PublicAPI
start(Name)->
    gen_fsm:start(?MODULE, [Name], []).

start_link(Name) ->
    gen_fsm:start_link(?MODULE, [Name], []).

%% helpers
notice(#state{name=N}, Str, Args) ->
    io:format("~s: "++Str++"~n", [N|Args]).

%% fsm - client
init(Name) ->
    {ok, idle, #state{name=Name}}.

idle({can_join, SupPid, OtherPid}, S=#state{}) ->
    gen_fsm:send_event(SupPid, {do_join, self()}),
    Ref = monitor(process, OtherPid),
    notice(S, "asking supervisor ~p for join conversation", [SupPid]),
    {next_state, idle_wait, S#state{supervisor_pid=SupPid, monitor=Ref}};
idle(Event, S=#state{}) ->
    notice(S, "unexpected event ~p in ~s state", [Event, "idle"]),
    {next_state, idle, S}.

idle_wait(no, S=#state{name=Name}) ->
    notice(S, "supervisor not accept join to conversation", []),
    {next_state, idle, #state{name=Name}};
idle_wait(ok, S=#state{supervisor_pid=SupPid}) ->
    gen_fsm:send_event(SupPid, ack_ok),
    notice(S, "supervisor accept join to new conversation", []),
    {next_state, texting, S};
idle_wait(ok_append, S=#state{}) ->
    notice(S, "supervisor accept join to existing conversation", []),
    {next_state, texting, S};
idle_wait(Event, S=#state{}) ->
    notice(S, "unexpected event ~p in ~s state", [Event, "idle_wait"]),
    {next_state, idle_wait, S}.


texting({write, Message}, S=#state{name=Name, supervisor_pid=SupPid}) ->
    gen_fsm:send_event(SupPid, {send_message, {self(), Name, Message}}),
    {next_state, texting, S};
texting({ask_join, Pid}, S=#state{}) ->
    notice(S, "supervisor asking join new client ~p", [Pid]),
    {next_state, ask_wait, S};
texting({receive_message, {Name, Message}}, S=#state{}) ->
    notice(S, "~s send message: ~s", [Name, Message]),
    {next_state, texting, S};
texting(end_converse, S=#state{supervisor_pid=SupPid}) ->
    gen_fsm:send_event(SupPid, {self(), end_texting}),
    {stop, normal, ok, S};
texting(Event, S=#state{}) ->
    notice(S, "unexpected event ~p in ~s state", [Event, "texting"]),
    {next_state, texting, S}.

ask_wait(accept, S=#state{supervisor_pid=SupPid}) ->
    gen_fsm:send_event(SupPid, yes),
    {next_state, texting, S};
ask_wait(decline, S=#state{supervisor_pid=SupPid}) ->
    gen_fsm:send_event(SupPid, no),
    {next_state, texting, S};
ask_wait(Event, S=#state{}) ->
    notice(S, "unexpected event ~p in ~s state", [Event, "ask_wait"]),
    {next_state, ask_wait, S}.

handle_sync_event(cancel, _From, _StateName, S = #state{supervisor_pid=SupPid}) ->
    gen_fsm:send_all_state_event(SupPid, cancel),
    {stop, cancelled, ok, S};
handle_sync_event(_Event, _From, StateName, Data) ->
    {next_state, StateName, Data}.

handle_event(cancel, _StateName, S=#state{}) ->
    notice(S, "received cancel event", []),
    {stop, other_cancelled, S};
handle_event(_Event, StateName, Data) ->
    {next_state, StateName, Data}.

handle_info({'DOWN', Ref, process, _Pid, Reason}, _, S=#state{monitor=Ref}) ->
    notice(S, "Other side dead", []),
    {stop, {other_down, Reason}, S};
handle_info(_Info, StateName, Data) ->
    {next_state, StateName, Data}.