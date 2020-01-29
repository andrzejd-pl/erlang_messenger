-module(main).
-compile(export_all).

run() ->
    {ok, SupPid} = messenger_fsm_supervisor:start_link(),
    % sys:trace(SupPid, true),
    {ok, ClientPidA} = messenger_fsm_client:start_link("Carl"),
    % sys:trace(ClientPidA, true),
    messenger_fsm_client:can_join(ClientPidA, SupPid),
    timer:sleep(100),
    {ok, ClientPidB} = messenger_fsm_client:start_link("John"),
    % sys:trace(ClientPidB, true),
    messenger_fsm_client:can_join(ClientPidB, SupPid),
    timer:sleep(100),
    ClientPidA.
    % messenger_fsm_client:accept(ClientPidA).