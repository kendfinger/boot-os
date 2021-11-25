import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:boot_os_tools/download.dart';
import 'package:boot_os_tools/hashlist.dart';
import 'package:boot_os_tools/lslr.dart';
import 'package:boot_os_tools/os.dart';
import 'package:boot_os_tools/sources.dart';
import 'package:boot_os_tools/util.dart';
import 'package:crypto/crypto.dart';

Never printUsageAndExit(ArgParser argp) {
  print("Usage: tools/bin/generate_debian_metadata.dart [options]");
  print("");
  print(argp.usage);
  if (argp.commands.isNotEmpty) {
    print("");
  }
  for (final commandName in argp.commands.keys) {
    print("Command: ${commandName}");
    print("");
    print(argp.commands[commandName]!.usage);
  }
  exit(1);
}

Future<void> main(List<String> argv) async {
  final argp = ArgParser();
  argp.addFlag("help", abbr: "h", help: "Show Command Usage", negatable: false);

  final cdImageCommand = ArgParser();
  cdImageCommand.addOption("mirror",
      abbr: "m",
      help: "Mirror URL",
      defaultsTo: "https://cdimage.debian.org/debian-cd/");
  cdImageCommand.addOption("search-path",
      abbr: "s", help: "Subdirectory Search Path");
  cdImageCommand.addOption("debian-version",
      abbr: "V", help: "Debian Version", mandatory: true);
  argp.addCommand("cdimage", cdImageCommand);

  ArgResults args;
  try {
    args = argp.parse(argv);
  } catch (e) {
    print(e);
    printUsageAndExit(argp);
  }

  if (args["help"]) {
    printUsageAndExit(argp);
  }

  final command = args.command;
  if (command == null) {
    printUsageAndExit(argp);
  }

  final commandName = command.name!;
  switch (commandName) {
    case "cdimage":
      await runCdimageTool(command);
      break;
    default:
      printUsageAndExit(argp);
  }
}

Future<void> runCdimageTool(ArgResults args) async {
  final mirrorUrl = Uri.parse(args["mirror"]);
  final mirrorIndexUrl = mirrorUrl.resolve("./ls-lR.gz");
  final http = HttpClient();
  final response = await http.getUrlStream(mirrorIndexUrl);
  final decompressedIndexStream = gzip.decoder.bind(response);
  final utf8IndexStream = utf8.decoder.bind(decompressedIndexStream);
  final linesIndexStream = LineSplitter().bind(utf8IndexStream);
  final index = await LslrIndexUnstructured.parse(linesIndexStream,
      fileBaseUrl: mirrorUrl);
  final structure = index.createFullStructure();

  var segmentToSearch = structure;

  final subdirectorySearchPath = args["search-path"];
  if (subdirectorySearchPath != null) {
    final actualSearchPath = "./" + subdirectorySearchPath;
    final subdirectories =
        structure.find(actualSearchPath, matchOnFullPath: true, exact: true);
    if (subdirectories.isEmpty) {
      throw Exception(
          "Failed to find target search directory ${subdirectorySearchPath}");
    }
    segmentToSearch = subdirectories.single;
  }

  final jigdoFiles = segmentToSearch.find(
      RegExp(r"^.*\/jigdo-cd\/debian\-[0-9].*\-netinst\.jigdo$"),
      matchOnFullPath: true);

  final files = <String, SourceFile>{};
  for (final jigdoFile in jigdoFiles) {
    final sha256ListUrl = jigdoFile.parent!.url.resolve("SHA256SUMS");
    final sha256ListContent = await http.getUrlString(sha256ListUrl);
    final hashList = HashList.parse(sha256, sha256ListContent.split("\n"));
    final jigdoFileName = jigdoFile.name;
    final baseFileName =
        jigdoFileName.substring(0, jigdoFileName.lastIndexOf(".jigdo"));
    final isoFileName = "$baseFileName.iso";
    final templateFileName = "$baseFileName.template";
    final templateFile = jigdoFile.parent!.find(templateFileName).single;

    final jigdoFileChecksum = hashList.files[jigdoFileName]!;
    final isoFileChecksum = hashList.files[isoFileName]!;
    final templateFileChecksum = hashList.files[templateFileName]!;

    final architecture = jigdoFile.parent!.parent!.name;
    final version = jigdoFile.name.split("-")[1];
    final file = SourceFile(
        "installer",
        architecture,
        "iso",
        version,
        null,
        SourceFileAssemble(
            "jigdo",
            Sources({
              jigdoFileName: SourceFile.assemble([jigdoFile.url.toString()],
                  null, SourceFileChecksums(jigdoFileChecksum, null)),
              templateFileName: SourceFile.assemble(
                  [templateFile.url.toString()],
                  null,
                  SourceFileChecksums(templateFileChecksum, null))
            })),
        SourceFileChecksums(isoFileChecksum, null));
    files[isoFileName] = file;
  }
  final debianVersionName = args["debian-version"];
  final sources = Sources(files);
  final osMetadata = OperatingSystemMetadata("debian", debianVersionName,
      files.values.map((e) => e.architecture).toSet().toList(), sources);
  final encoded = osMetadata.encode();
  removeAllNullValues(encoded);
  print(const JsonEncoder.withIndent("  ").convert(encoded));
  http.close();
}
