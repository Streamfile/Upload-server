%%%-------------------------------------------------------------------
%%% @author Niclas Axelsson <niclas@burbas.se>
%%% @copyright (C) 2014-2015, Niclas Axelsson
%%% @doc
%%% Worker module for the upload server
%%% @end
%%% Created : 15 May 2014 by Niclas Axelsson <niclas@burbas.se>
%%%-------------------------------------------------------------------
-module(upload_server_worker).

-behaviour(gen_server).

%% API
-export([start/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
          stream_id = "",
          file_count = 1,
          total_files = 1,
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
start(StreamID, MaxFileSize, User, FileCount) ->
    gen_server:start(?MODULE, [StreamID, MaxFileSize, User, FileCount], []).

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
init([StreamID, MaxFileSize, User, FileCount]) ->
    {ok, #state{
       stream_id = StreamID,
       user = User,
       max_file_size = MaxFileSize,
       total_files = FileCount
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

%% COMPLETE FILES WITHOUT CHUNKING
handle_call({new_part, undefined, Params, [File]}, _From, State = #state{
                                                            stream_id = StreamID,
                                                            total_files = TotalFileCount,
                                                            file_count = TotalFileCount,
                                                            files = Files,
                                                            current_file_size = CFS,
                                                            max_file_size = MFS
                                                           }) when MFS >= CFS ->
    case TotalFileCount of
        1 ->
            %% We just return the file
            CurrentFile = [
                           {original_name, proplists:get_value("name", Params)},
                           {temp_file, sb_uploaded_file:temp_file(File)},
                           {size, sb_uploaded_file:size(File)}
                          ],
            {stop, {normal, StreamID}, {ok, File}, State#state{files = [CurrentFile|Files]}};
        _ ->
            %% Zip the files and return
            Filename = archive_files([File|Files]),
            {stop, {normal, StreamID}, {ok, Filename}, State}
    end;
handle_call({new_part, undefined, Params, [File]}, _From, State = #state{
                                                            file_count = FileCount,
                                                            files = Files,
                                                            current_file_size = CFS,
                                                            max_file_size = MFS
                                                           }) when MFS >= CFS ->


    {reply, ok, State};

%% FILES WITH CHUNKING
handle_call({new_part, ChunkNo, Params, [File]}, _From, State = #state{
                                                          stream_id = StreamID,
                                                          file_count = FC,
                                                          files = Files,
                                                          chunks = Chunks,
                                                          current_file_size = CFS,
                                                          max_file_size = MFS
                                                         }) when MFS >= CFS ->
    %% Check which chunk this is
    ChunksInt = erlang:list_to_integer(proplists:get_value("chunks", Params, "1")),
    case ChunksInt-1 of
        ChunkNo ->
            %% This is the last chunk so let's concat the whole thing
            FinishedFile = pack_file([File|Chunks]),
            {stop, {normal, StreamID}, {ok, FinishedFile}, State#state{chunks = [], file_count = FC+1, files = Files}};
        _ ->
            %% We are currently receiving a chunk
            {reply, ok, State#state{chunks = [File|Chunks], current_file_size = sb_uploaded_file:size(File) + CFS}}
    end;

handle_call({new_part, _Params, _File}, _From, State) ->
    {stop, {file_to_big, State#state.stream_id}, State};
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
    %TempFiles = [ sb_uploaded_file:temp_file(X) || X <- Chunks ++ Files ],
    %os:cmd(lists:concat(["rm ", string:join(TempFiles, " ")])),
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
pack_file(Chunks) ->
    Filename = lists:concat([sb_uploaded_file:temp_file(hd(Files)), "_fin"]),
    TempFiles = [ sb_uploaded_file:temp_file(X) || X <- Files ],
    os:cmd(lists:concat(["cat ", string:join(lists:reverse(TempFiles), " "), " > ", Filename])),
    %% Remove all the file pieces
    CMD = lists:concat(["rm ", string:join(TempFiles, " ")]),
    io:format("~p~n", [CMD]),
    os:cmd(CMD),
    %% Return the filename for the zip
    Filename.
