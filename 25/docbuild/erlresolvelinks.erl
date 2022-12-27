%%--------------------------------------------------------------------
%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2009-2020. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
%%-----------------------------------------------------------------
%% File: erlresolvelinks.erl
%% 
%% Description:
%%    This file generates the javascript that resolves documentation links.
%%
%%-----------------------------------------------------------------
-module(erlresolvelinks). 

-export([make/1]).
-include_lib("kernel/include/file.hrl").

-define(JAVASCRIPT_NAME, "erlresolvelinks.js").

make([ErlTop, RootDir, DestDir]) ->
    make(ErlTop, RootDir, DestDir).

make(ErlTop, RootDir, DestDir) ->
    %% doc/Dir
    %% erts-Vsn
    %% lib/App-Vsn
    Name = ?JAVASCRIPT_NAME,
    DocDirs0 = get_dirs(filename:join([ErlTop, "system/doc"])),
    DocDirs = lists:map(fun({Dir, _DirPath}) -> 
				D = filename:join(["doc", Dir]),
				{D, D} end, DocDirs0),

    Released = ErlTop /= RootDir,

    ErtsDirs = latest_app_dirs(Released, RootDir, ""), 
    AppDirs = latest_app_dirs(Released, RootDir, "lib"),
    
    AllAppDirs = 
	lists:map(
	  fun({App, AppVsn}) -> {App, filename:join([AppVsn, "doc", "html"])}
	  end, ErtsDirs ++ AppDirs),

    AllDirs = DocDirs ++ AllAppDirs,
    {ok, Fd} = file:open(filename:join([DestDir, Name]), [write]),
    UTC = calendar:universal_time(),
    io:fwrite(Fd, "/* Generated by ~s at ~w UTC */\n", 
	      [atom_to_list(?MODULE), UTC]),
    io:fwrite(Fd, "function erlhref(ups, app, rest) {\n", []),
    io:fwrite(Fd, "    switch(app) {\n", []),
    lists:foreach(
      fun({Tag, Dir}) ->
	      io:fwrite(Fd, "    case ~p:\n", [Tag]),
	      io:fwrite(Fd, "        location.href=ups + \"~s/\" + rest;\n",
			[Dir]),
	      io:fwrite(Fd, "        break;\n",	[])
      end, AllDirs),
    io:fwrite(Fd, "    default:\n", []),
    io:fwrite(Fd, "        location.href=ups + \"Unresolved\";\n", []),
    io:fwrite(Fd, "    }\n", []),
    io:fwrite(Fd, "}\n", []),
    file:close(Fd),
    ok.
   



get_dirs(Dir) ->
    {ok, Files} = file:list_dir(Dir),
    AFiles = 
	lists:map(fun(File) -> {File, filename:join([Dir, File])} end, Files),
    lists:zf(fun is_dir/1, AFiles).

is_dir({File, AFile}) ->
    {ok, FileInfo} = file:read_file_info(AFile),
    case FileInfo#file_info.type of
	directory ->
	    {true, {File, AFile}};
	_  ->
	    false
    end.

released_app_vsns([]) ->
    [];
released_app_vsns([{AppVsn, Dir} | AVDirs]) ->
    try
        {ok, _} = file:read_file_info(filename:join([Dir, "doc", "html"])),
        [App, Vsn] = string:tokens(AppVsn, "-"),
        VsnNumList = vsnstr_to_numlist(Vsn),
        [_Maj, _Min | _] = VsnNumList,
        [{{App, VsnNumList}, AppVsn} | released_app_vsns(AVDirs)]
    catch
        _:_ -> released_app_vsns(AVDirs)
    end.

latest_app_dirs(Release, RootDir, Dir) ->
    ADir = filename:join(RootDir, Dir),
    RDirs0 = get_dirs(ADir),
    SDirs0 = case Release of
                 true ->
                     released_app_vsns(RDirs0);
                 false ->
                     lists:map(fun({App, Dir1}) ->
                                       File = filename:join(Dir1, "vsn.mk"),
                                       case file:read_file(File) of
                                           {ok, Bin} ->
                                               case re:run(Bin, ".*VSN\s*=\s*([0-9\.]+).*",[{capture,[1],list}]) of
                                                   {match, [VsnStr]} ->
                                                       VsnNumList = vsnstr_to_numlist(VsnStr),
                                                       {{App, VsnNumList}, App++"-"++VsnStr};
                                                   nomatch ->
                                                       io:format("No VSN variable found in ~s\n", [File]),
                                                       error
                                               end;
                                           {error, Reason} ->
                                               io:format("~p : ~s\n", [Reason, File]),
                                               error
                                       end
                               end, 
                               lists:filter(fun is_app_dir/1, RDirs0))
             end,

     SDirs1 = lists:keysort(1, SDirs0),
     App2Dirs = lists:foldr(fun({{App, _VsnNumList}, AppVsn}, Acc) ->
 				   case lists:keymember(App, 1, Acc) of
 				       true ->
 					   Acc;
 				       false ->
 					   [{App, AppVsn}| Acc]
 				   end
 			   end, [], SDirs1),
    lists:map(fun({App, AppVsn}) -> {App, filename:join([Dir, AppVsn])} end,
 	      App2Dirs).

is_app_dir({_Dir, DirPath}) ->
    case file:read_file_info(filename:join(DirPath, "vsn.mk")) of
	{ok, FileInfo} ->
	    case FileInfo#file_info.type of
		regular ->
		    true;
		_  ->
		    false
	    end;
	{error, _Reason} ->
	    false
    end.


%% is_vsnstr(Str) ->	
%%     case string:tokens(Str, ".") of
%% 	[_] ->
%% 	    false;
%% 	Toks  ->
%% 	    lists:all(fun is_numstr/1, Toks)
%%     end.

%% is_numstr(Cs) ->
%%     lists:all(fun(C) when $0 =< C, C =< $9 -> 
%% 		      true;
%% 		 (_) ->
%% 		      false
%% 	      end, Cs).

%% We know:

vsnstr_to_numlist(VsnStr) ->	    
    lists:map(fun(NumStr) -> list_to_integer(NumStr) end,
	      string:tokens(VsnStr, ".")).


     


    

