import 'dart:convert';
import 'dart:io';

import 'package:app_installer/app_installer.dart';
import 'package:easy_app_installer/easy_app_installer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tripmate/class/app_package.dart';
import 'package:http/http.dart' as http;
import 'package:tripmate/class/tool/setting.dart';
import 'package:tripmate/class/tool/tool.dart';
import 'package:tripmate/config/config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tripmate/route/route_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/**
 *@Author: ZhanshuoBai
 *@CreateTime: 2025-04-07
 *@Description:用于踏浪应用更新页面，当其他页面传入arguments参数时候显示arguments中的AppPackage对象信息；当没有arguments参数传入时候，获取当前设置中更新渠道的最新版本信息并检查是否需要更新和此版本是否强制更新，如果需要强制更新则禁用返回功能。此外代码实现了安装包文件的中断接续下载，用户下载安装包的过程中退出应用或者出现网络连接问题导致下载中断，当用户再次下载的时候将会接续下载而不必覆盖重写。并且实现了安装包文件的完整性校验，当安装包损坏的时候认为下载异常，则执行删除重新下载的操作。在此分享代码，共大家学习交流。也欢迎大家加入QQ社群：1041572024一起学习flutter、SpringBoot或者交流反馈应用。
 *@Version: 1.0
 */

class UpdatePackagePage extends StatefulWidget {
  UpdatePackagePage({super.key});

  @override
  State<UpdatePackagePage> createState() => _UpdatePackagePageState();
}

class _UpdatePackagePageState extends State<UpdatePackagePage> {
  AppPackage? appPackage;
  double downloadProgress = 0.0;
  bool isDownloading = false;
  int? downloadedBytes;
  bool isDownloadComplete = false;
  bool isLastestVersion = false;


  Setting setting = Setting();

  Future<void> downloadFile() async {
    if (appPackage == null) {
      print('应用包信息为空，无法下载');
      return;
    }

    if (isDownloadComplete) {
      final filePath = '${Directory.systemTemp.path}/${appPackage!.version_code}.apk';
      await installApp(filePath);
      return;
    }

    // 检查存储权限
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        print('未授予存储权限，无法下载');
        return;
      }
    }

    setState(() {
      isDownloading = true;
    });
    final url = Uri.parse(appPackage!.file_url);
    final filePath = '${Directory.systemTemp.path}/${appPackage!.version_code}.apk';
    final file = File(filePath);

    int totalLength = await getTotalLength();
    if (await file.exists()) {
      downloadedBytes = await file.length();
      if (downloadedBytes == totalLength) {
        setState(() {
          isDownloading = false;
          isDownloadComplete = true;
        });
        await installApp(filePath);
        return;
      }
    } else {
      downloadedBytes = 0;
    }

    final request = http.Request('GET', url);
    if (downloadedBytes != null && downloadedBytes! > 0) {
      request.headers['Range'] = 'bytes=$downloadedBytes-';
    }

    try {
      final response = await http.Client().send(request);
      int? contentLength;
      if (response.contentLength != null && downloadedBytes != null) {
        contentLength = response.contentLength! + downloadedBytes!;
      } else {
        print('无法获取文件总长度，认为安装包损坏，重新下载');
        // 删除已下载的文件
        if (await file.exists()) {
          await file.delete();
        }
        // 重置下载进度
        downloadedBytes = 0;
        downloadProgress = 0.0;
        setState(() {
          isDownloading = false;
        });
        // 重新下载
        await downloadFile();
        return;
      }

      var bytesReceived = downloadedBytes!;

      final output = file.openWrite(mode: FileMode.append);

      response.stream.listen((List<int> chunk) {
        bytesReceived += chunk.length;
        setState(() {
          downloadProgress = bytesReceived / contentLength!;
        });
        output.add(chunk);
      }, onDone: () async {
        await output.close();
        setState(() {
          isDownloading = false;
          isDownloadComplete = true;
        });
        await installApp(filePath);
      }, onError: (e) async {
        await output.close();
        setState(() {
          isDownloading = false;
          isDownloadComplete = false;
        });
        print('下载出错: $e');
      });
    } catch (e) {
      setState(() {
        isDownloading = false;
        isDownloadComplete = false;
      });
      print('网络请求出错: $e');
    }
  }

  Future<void> installApp(String filePath) async {
    try {
      await EasyAppInstaller.instance.installApk(filePath);
    } catch (e) {
      print('安装应用出错: $e');
    }
  }

  Widget buildAppHeadBar() {
    if (appPackage == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
      child: Column(
        children: [
          Row(
            children: [
              //图标logo
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 0,
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    "assets/icons/ic_launcher.png",
                    width: 90,
                    height: 90,
                  ),
                ),
              ),
              Container(
                height: 90,
                // width: 120,
                margin: const EdgeInsets.only(left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const Text(
                      "踏浪",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      appPackage!.version_name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const Text(
                      "黑ICP备2024017115号-4A",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildAppUpdateDecoration() {
    return Container(
      margin: const EdgeInsets.only(top: 20, left: 20, right: 20),
      width: double.infinity,
      child: Column(
        children: [
          Card(
            child: Container(
              margin: const EdgeInsets.all(16),
              width: double.infinity,
              child: const Column(
                children: [
                  Text(
                    "“流畅旅行轻松规划”",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAppUpdateInfo() {
    if (appPackage == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 20, left: 20, right: 20),
      child: Column(
        children: [
          ///新版特性
          Row(
            children: [
              const Text(
                "新版特性",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
               Expanded(child: Container()),
              Text(
                "${appPackage!.update_datetime.year}-${appPackage!.update_datetime.month}-${appPackage!.update_datetime.day}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
           SizedBox.fromSize(size: Size.fromHeight(5)),
          Container(
            margin: const EdgeInsets.only(top: 5, left: 5, right: 5),
            width: MediaQuery.of(context).size.width, //屏幕宽度
            child: Text(
              appPackage!.update_content,
              maxLines: null,
              overflow: TextOverflow.visible,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
           SizedBox.fromSize(size: Size.fromHeight(10)),
          ///应用介绍
          Row(
            children: [
              const Text(
                "应用介绍",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
           SizedBox.fromSize(size: Size.fromHeight(5)),
          Container(
            margin: const EdgeInsets.only(top: 5, left: 5, right: 5),
            width: MediaQuery.of(context).size.width, //屏幕宽度
            child: Text(
              appPackage!.description,
              maxLines: null,
              overflow: TextOverflow.visible,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
           SizedBox.fromSize(size: Size.fromHeight(10)),
          ///其他信息
          Row(
            children: [
              const Text(
                "其他信息",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
           SizedBox.fromSize(size: Size.fromHeight(5)),
          Container(
            margin: const EdgeInsets.only(top: 5, left: 5, right: 5),
            width: MediaQuery.of(context).size.width, //屏幕宽度
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "开发者:白展硕\n更新时间:${appPackage!.update_datetime.year}-${appPackage!.update_datetime.month}-${appPackage!.update_datetime.day}\n版本号:${appPackage!.version_name}\n",
                  maxLines: null,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                GestureDetector(
                  onTap: () async {
                    const url = 'http://www.surfroute.cn'; // 替换为实际的官网地址
                    if (await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(Uri.parse(url));
                    } else {
                      print('无法打开网页');
                    }
                  },
                  child: RichText(
                    text: TextSpan(
                      text: '下载失败？前往浏览器官网下载',
                      style:  TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
           SizedBox.fromSize(size: Size.fromHeight(100)),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    checkDownloadStatus();
  }

  Future<void> checkDownloadStatus() async {
    if (appPackage != null) {
      final filePath = '${Directory.systemTemp.path}/${appPackage!.version_code}.apk';
      final file = File(filePath);
      if (await file.exists()) {
        final totalLength = await getTotalLength();
        final fileLength = await file.length();
        if (fileLength == totalLength) {
          setState(() {
            isDownloadComplete = true;
            downloadProgress = 1.0;
          });
        }
      }
    }
  }

  Future<int> getTotalLength() async {
    if (appPackage == null) {
      return 0;
    }
    final url = Uri.parse(appPackage!.file_url);
    final request = http.Request('HEAD', url);
    try {
      final response = await http.Client().send(request);
      return response.contentLength?? 0;
    } catch (e) {
      print('获取文件总长度出错: $e');
      return 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments != null) {
      appPackage = arguments as AppPackage;
    } else {
      fetchAppPackage();
    }
  }

  Future<void> fetchAppPackage() async {
    try {
      await Setting.readSettingFromFile().then((value){
        print(value);
        if(value != null){
          setState(() {
            setting = Setting.fromJson(jsonDecode(value));
          });
        }else{

        }
      }).then((value) async {
        var request = http.Request('GET', Uri.parse('${ConstConfig.server_url}/app/info/last/${setting.check_update_platform}'));
        var response = await request.send();
        if (response.statusCode == 200) {
          var responseJson = await response.stream.bytesToString();
          if(jsonDecode(responseJson)['data'] == null){
            Tools.showToast("暂无${setting.check_update_platform}平台更新");
            RouteUtils.pop(context);
          }else{
            setState(() {
              appPackage = AppPackage.fromMap(jsonDecode(responseJson)['data']);
            });
            if(appPackage!.version_code>ConstConfig.appPackage.version_code){
              Tools.showToast("发现${setting.check_update_platform}平台更新");
            }else{
              Tools.showToast("当前已是最新版本");
              setState(() {
                isLastestVersion = true;
              });
            }
          }

        } else {
          print('检查更新失败，状态码: ${response.statusCode}');
        }
      });

    } catch (e) {
      print('检查更新时出现错误: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (appPackage == null) {
      return Scaffold(
        appBar: AppBar(
          title: isLastestVersion ?Text("最近更新"): Text('新版本'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async => isLastestVersion?true:!(appPackage!.forced_update),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: isLastestVersion?true:!(appPackage!.forced_update),
          title: isLastestVersion ?Text("最近更新"): Text('新版本'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: isDownloading ? null : downloadFile,
          icon: const Icon(Icons.download_outlined),
          label: Text(
            isDownloading
                ? '下载进度：${(downloadProgress * 100).toStringAsFixed(0)}%'
                : isDownloadComplete
                ? '立即安装'
                : '更新应用',
          ),
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              buildAppHeadBar(),
              buildAppUpdateDecoration(),
              buildAppUpdateInfo(),
            ],
          ),
        ),
      ),
    );
  }
}
