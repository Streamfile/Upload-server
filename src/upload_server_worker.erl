%%%-------------------------------------------------------------------
%%% @author Niclas Axelsson <burbas@Niclass-MacBook-Pro-2.local>
%%% @copyright (C) 2014, Niclas Axelsson
%%% @doc
%%%
%%% @end
%%% Created : 15 May 2014 by Niclas Axelsson <burbas@Niclass-MacBook-Pro-2.local>
%%%-------------------------------------------------------------------
-module(upload_server_worker).

-behaviour(gen_server).

%% API
-export([start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
          stream_id = "",
          file_count = 1,
          files = [],
          chunks = [],
          current_file_size = 0,
          max_file_size = 0,
          user
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
start_link(StreamID, MaxFileSize, User) ->
    gen_server:start_link(?MODULE, [StreamID, MaxFileSize, User], []).

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
init([StreamID, MaxFileSize, User]) ->
    {ok, #state{
       stream_id = StreamID,
       user = User,
       max_file_size = MaxFileSize
      }}.

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
handle_call({new_part, undefined, Params, File}, _From, State = #state{
                                                      files = Files,
                                                      current_file_size = CFS,
                                                      max_file_size = MFS
                                                     }) when MFS >= CFS ->
    %% This file is not chunked. Just let it pass
    FinishedFile = [{original_name, proplists:get_value("name", Params)}, {temp_file, File:temp_file()}, {size, File:size()}],
    {reply, {file, File}, State#state{files = [FinishedFile|Files]}};

handle_call({new_part, Chunk, Params, File}, _From, State = #state{
                                                      file_count = FC,
                                                      files = Files,
                                                      chunks = Chunks,
                                                      current_file_size = CFS,
                                                      max_file_size = MFS
                                                     }) when MFS >= CFS ->
    %% Check which chunk this is
    ChunkInt = erlang:list_to_integer(Chunk),
    ChunksInt = erlang:list_to_integer(proplists:get_value("chunks", Params, Chunk)),
    case ChunksInt-1 of
        ChunkInt ->
            %% This is the last chunk so let's concat the whole thing
            TempFiles = [ X:temp_file() || X <- [File|Chunks] ],
            os:cmd(lists:concat(["cat ", string:join(lists:reverse(TempFiles), " "), " > ", File:temp_file(), "_fin"])),
            %% Remove all the file pieces
            os:cmd(lists:concat(["rm ", string:join(TempFiles, " ")])),
            %% Store the file information
            FinishedFile = [{original_name, proplists:get_value("name", Params)}, {temp_file, File:temp_file() ++ "_fin"}, {size, File:size() + CFS}],
            {reply, {ok, FinishedFile}, State#state{chunks = [], file_count = FC+1, files = [FinishedFile|Files]}};
        _ ->
            %% We are currently receiving a chunk
            {reply, ok, State#state{chunks = [File|Chunks], current_file_size = File:size() + CFS}}
    end;
handle_call({new_part, _Params, _File}, _From, State) ->
    {stop, file_to_big, {error, file_to_big}, State};
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
terminate(_Reason, #state{chunks = Chunks, files = Files}) ->
    %% Remove all the files we've gathered during this transfer
    TempFiles = [ X:temp_file() || X <- Chunks ++ Files ],
    os:cmd(lists:concat(["rm ", string:join(TempFiles, " ")])),
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
