-module(messenger_fsm_supervisor).
-behaviour(gen_fsm).

-export([init/1, idle/2, idle_wait/2, conversations/2, handle_info/3, handle_sync_event/4, handle_event/3, start/0, start_link/0]).

-record(message, {client_pid, client_name, message=""}).
-record(state, {name, clients=[], messages=[], new_pid}).


%% helpers
notice(#state{name=N}, Str, Args) ->
    io:format("~s: "++Str++"~n", [N|Args]).

send_cancel_to_all([ClientPid]) ->
    gen_fsm:send_all_state_event(ClientPid, cancel);
send_cancel_to_all([ClientPid|T]) ->
    gen_fsm:send_all_state_event(ClientPid, cancel),
    send_cancel_to_all(T).

send_to_all_clients([], _) ->
    nothing;
send_to_all_clients([ClientPid], State) ->
    gen_fsm:send_event(ClientPid, State);
send_to_all_clients([ClientPid|T], State) ->
    gen_fsm:send_event(ClientPid, State).

remove(X, L) ->
    [Y || Y <- L, Y =/= X].

%% fsm - Public API
start()->
    gen_fsm:start(?MODULE, ["Supervisor"], []).

start_link() ->
    gen_fsm:start_link(?MODULE, ["Supervisor"], []).

init(Name) ->
    {ok, idle, #state{name=Name}}.

idle({do_join, Pid}, S=#state{}) ->
    gen_fsm:send_event(Pid, ok),
    {next_state, idle_wait, S#state{clients=[Pid]}};
idle(_Event, S=#state{}) ->
    {next_state, idle, S}.

idle_wait(ack_ok, S=#state{}) ->
    {next_state, conversations, S};
idle_wait(Event, Data) ->
    io:format("~p ~n", [Event]),
    {next_state, idle_wait, Data}.

conversations({do_join, Pid}, S=#state{clients=Clients}) ->
    send_to_all_clients(Clients, {ask_join, Pid}),
    {next_state, append, S#state{new_pid=Pid}};
conversations({ClientPid, ClientName, ClientMessage}, S=#state{clients=Clients, messages=Messages}) ->
    send_to_all_clients(remove(ClientPid, Clients), {ClientName, ClientMessage}),
    {next_state, conversations, S#state{messages=Messages ++ [#message{client_pid=ClientPid, client_name=ClientName, message=ClientMessage}]}};
conversations({ClientPid, end_texting}, S=#state{clients=Clients}) ->
    if length(Clients) == 1 ->
        {next_state, idle, S#state{clients=[]}};
    true -> 
        {next_state, conversations, S#state{clients=remove(ClientPid, Clients)}}
    end;
conversations(Event, Data) ->
    io:format("~p ~n", [Event]),
    {next_state, conversations, Data}.

append(yes, S=#state{clients=Clients, new_pid=Pid}) ->
    gen_fsm:send_event(Pid, ok_append),
    {next_state, conversations, S#state{clients=Clients ++ [Pid]}};
append(no, S=#state{new_pid=Pid}) ->
    gen_fsm:send_event(Pid, no),
    {next_state, conversations, S};
append(Event, Data) -> 
    io:format("~p ~n", [Event]),
    {next_state, append, Data}.

handle_sync_event(cancel, _From, _StateName, S=#state{clients=ClientPids}) ->
    send_cancel_to_all(ClientPids),
    {stop, cancelled, ok, S};
handle_sync_event(Event, _From, StateName, Data) ->
    io:format("~p ~n", [Event]),
    {next_state, StateName, Data}.

handle_event(cancel, _StateName, S=#state{clients=ClientPids}) ->
    send_cancel_to_all(ClientPids),
    notice(S, "received cancel event", []),
    {stop, other_cancelled, S};
handle_event(_Event, StateName, Data) ->
    {next_state, StateName, Data}.

handle_info({'DOWN', _Ref, process, _Pid, Reason}, _, S=#state{}) ->
    notice(S, "Other side dead", []),
    {stop, {other_down, Reason}, S};
handle_info(_Info, StateName, Data) ->
    {next_state, StateName, Data}.