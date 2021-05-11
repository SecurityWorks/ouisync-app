import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ouisync_plugin/ouisync.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:styled_text/styled_text.dart';

import '../bloc/blocs.dart';
import '../controls/controls.dart';
import '../data/data.dart';
import '../models/models.dart';
import '../utils/utils.dart';
import 'pages.dart';

class RootPage extends StatefulWidget {
  RootPage({
    Key key,
    @required this.reposBaseFolderPath,
    @required this.foldersRepository,
    this.title,
  }) :
  assert(reposBaseFolderPath != null),
  assert(reposBaseFolderPath != ""), 
  assert(foldersRepository != null),
  super(key: key);

  final String reposBaseFolderPath;
  final DirectoryRepository foldersRepository;
  final String title;

  @override
  _RootPageState createState() => _RootPageState();
}

class _RootPageState extends State<RootPage>
  with TickerProviderStateMixin {

  AnimationController _controller;
  
  Color backgroundColor;
  Color foregroundColor;

  StreamSubscription _intentDataStreamSubscription;
  List<SharedMediaFile> _sharedFiles;

  @override
  void initState() {
    initRepositories();

    // For sharing images coming from outside the app while the app is in the memory
    _intentDataStreamSubscription =
        ReceiveSharingIntent.getMediaStream().listen((List<SharedMediaFile> value) {
      setState(() {
        print("Shared:" + (_sharedFiles?.map((f)=> f.path)?.join(",") ?? ""));
        _sharedFiles = value;
      });
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });

    // For sharing images coming from outside the app while the app is closed
    ReceiveSharingIntent.getInitialMedia().then((List<SharedMediaFile> value) {
      setState(() {
        _sharedFiles = value;
      });
    });

    _controller = new AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: actionsFloatingActionButtonAnimationDuration),
    );

    super.initState();
  }

  @override
  void dispose() {
    super.dispose();

    _intentDataStreamSubscription.cancel();
    _controller.dispose();
  }

  Future<void> initRepositories() async {
    bool exist = await Directory(widget.reposBaseFolderPath).exists();
    if (!exist) {
      print('No repositories were found');
      BlocProvider.of<RepositoryBloc>(context)
      .add(
        RepositoriesRequest(
          repositoriesPath: widget.reposBaseFolderPath
        )
      );

      return;
    }

    List<FileSystemEntity> repoList = await Directory(widget.reposBaseFolderPath).list().toList();
    print('Repositories found ${repoList.length}:\n$repoList');

    initializeUserRepositories(repoList.map((e) => e.path).toList())
    .then((value) async => 
      BlocProvider.of<RepositoryBloc>(context)
      .add(
        RepositoriesRequest(
          repositoriesPath: widget.reposBaseFolderPath
        )
      )
    );
  }

  Future<void> initializeUserRepositories(List<String> reposList) async {
    reposList.forEach((repo) => {
      print('About to initilialize $repo'),
      OuiSync.initializeRepository(repo)
    });
  }

  @override
  Widget build(BuildContext context) {
    backgroundColor = Theme.of(context).cardColor;
    foregroundColor = Theme.of(context).accentColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget> [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () async {

            },
          )
        ]
      ),
      drawer: Drawer(
        child: Center(child: DrawerMenu()),
      ),
      body: _repositoriesBlocBuilder(),
      floatingActionButton: Dialogs.floatingActionsButtonMenu(
        BlocProvider.of<RepositoryBloc>(context),
        context,
        _controller,
        widget.reposBaseFolderPath,
        '',//parentPath
        repoActions,
        flagRepoActionsDialog,
        backgroundColor,
        foregroundColor
      ),
    );
  }

  Widget _repositoriesBlocBuilder() {
    return Center(
        child: BlocBuilder<RepositoryBloc, RepositoryState>(
            builder: (context, state) {
              if (state is RepositoryInitial) {
                return Center(child: Text('Loading repositories...'));
              }

              if (state is RepositoryLoadInProgress){
                return Center(child: CircularProgressIndicator());
              }

              if (state is RepositoryLoadSuccess) {
                return state.repositories.isEmpty
                ? _noRepos()
                : _reposListView(context, state.repositories);
              }

              if (state is RepositoryLoadFailure) {
                return Text(
                  'Something went wrong!',
                  style: TextStyle(color: Colors.red),
                );
              }

              return Center(child: Text('repos_'));
            }
        )
    );
  }

  _noRepos() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Align(
        alignment: Alignment.center,
        child: Text(
          messageNoRepos,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24.0,
            fontWeight: FontWeight.bold
          ),
        ),
      ),
      SizedBox(height: 20.0),
      Align(
        alignment: Alignment.center,
        child: StyledText(
          text: messageCreateNewRepoStyled,
          style: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.normal
          ),
          styles: {
            'bold': TextStyle(fontWeight: FontWeight.bold),
            'arrow_down': IconStyle(Icons.south),
          },
        ),
      ),
    ],
  );

  _reposListView(BuildContext context, List<BaseItem> repositories) => ListView.builder(
    itemCount: repositories.length,
    itemBuilder: (context, index) {
      final repo = repositories[index];
      return RepoDescription(
        folderData: repo,
        isEncrypted: false,
        isLocal: true,
        isOwn: true,
        action: () => _navigateToRepositoryContents(
          context: context,
          repoPath: repo.path,
          title: repo.name
        )
      );
    },
  );

  void _navigateToRepositoryContents({BuildContext context, String repoPath, String title}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) {
        return BlocProvider(
          create: (context) => DirectoryBloc(
            repository: widget.foldersRepository
          ),
          child: FolderPage(
            repoPath: repoPath,
            folderPath: '',
            foldersRepository: widget.foldersRepository,
            title: title
          )
        );
      })
    );
  }
}