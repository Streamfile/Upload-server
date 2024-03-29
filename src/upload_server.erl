%%%-------------------------------------------------------------------
%%% @author Niclas Axelsson <niclas@burbas.se>
%%% @copyright (C) 2014, Niclas Axelsson
%%% @doc
%%% Main interface for upload-server
%%% @end
%%% Created : 15 May 2014 by Niclas Axelsson <niclas@burbas.se>
%%%-------------------------------------------------------------------
-module(upload_server).

-behaviour(gen_server).

%% API
-export([
         start_link/0,
         checkout/3,
         report_part/5
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
          workers
         }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({global, ?SERVER}, ?MODULE, [], []).


checkout(Identifier, User, FileCount) ->
    gen_server:call({global, ?MODULE}, {checkout, Identifier, User, FileCount}).

report_part(Identifier, User, Chunk, Params, File) when is_integer(Chunk) ->
    FileCount = proplists:get_value("file_count", Params, "1"),
    {ok, Worker} = checkout(Identifier, User, erlang:list_to_integer(FileCount)),
    gen_server:call(Worker, {new_part, Chunk, Params, File});
report_part(Identifier, User, Chunk, Params, File) when is_list(Chunk) ->
    report_part(Identifier, User, erlang:list_to_integer(Chunk), Params, File);
report_part(Identifier, User, _Chunk, Params, File) ->
    report_part(Identifier, User, 0, Params, File).



%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    Workers = dict:new(),
    {ok, #state{workers = Workers}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({checkout, Identifier, User, FileCount}, _From, State = #state{workers = Workers}) ->
    case dict:find(Identifier, Workers) of
        {ok, Worker} ->
            {reply, {ok, Worker}, State};
        _ ->
            %% Create a new worker
            MaxFileSize = user_lib:upload_limit(User) * 1024,
            {ok, Pid} = upload_server_worker:start(Identifier, MaxFileSize, User, FileCount),
            {reply, {ok, Pid}, State#state{workers = dict:store(Identifier, Pid, Workers)}}
    end;

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({'EXIT', _Pid, {normal, Identifier}}, State) ->
    Workers = dict:erase(Identifier, State#state.workers),
    {noreply, State#state{workers = Workers}};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
generate_id() ->
    random:seed(now()),
    Id = generate_id1([], 12).

generate_id1(Acc, MaxLength) when length(Acc) == MaxLength ->
    Acc;
generate_id1(Acc, MaxLength) ->
    case random:uniform(62) of
        I when I =< 10 ->
            generate_id1([47+I | Acc], MaxLength);
        I when I =< 36 ->
            generate_id1([54+I | Acc], MaxLength);
        I ->
            generate_id1([60+I | Acc], MaxLength)
    end.
