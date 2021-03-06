library boot.os.tools.lslr;

class LslrIndexUnstructured {
  final Uri fileBaseUrl;
  final Map<String, List<LslrFileEntry>> entries;

  LslrIndexUnstructured(this.fileBaseUrl, this.entries);

  @override
  String toString() => "LslrIndexUnstructured(${entries})";

  LslrEntity createFullStructure() {
    var allDirectoryPaths = entries.keys.toList();
    allDirectoryPaths.sort((a, b) {
      final aDepth = a.codeUnits
          .map((e) => String.fromCharCode(e))
          .where((x) => x == "/")
          .length;
      final bDepth = b.codeUnits
          .map((e) => String.fromCharCode(e))
          .where((x) => x == "/")
          .length;
      return aDepth.compareTo(bDepth);
    });

    final directories = <String, LslrEntity>{};

    for (final path in allDirectoryPaths) {
      final parts = path.split("/");
      final parentPath = parts.take(parts.length - 1).join("/");
      final parent = directories[parentPath];
      final entity = LslrEntity(fileBaseUrl, parts.last);
      entity.parent = parent;
      entity.isFile = false;
      directories[path] = entity;
    }

    for (final path in allDirectoryPaths) {
      final directory = directories[path];
      final allFileEntries = entries[path]!;
      for (final entry in allFileEntries) {
        final entryPath = "$path/${entry.name}";

        LslrEntity entity;
        if (directories.containsKey(entryPath)) {
          entity = directories[entryPath]!;
        } else {
          entity = LslrEntity(fileBaseUrl, entry.name);
          entity.parent = directory;
          entity.fileEntry = entry;
        }

        if (directory != null) {
          directory.children.add(entity);
        }
      }
    }

    return directories.entries
        .firstWhere((entry) => entry.value.parent == null)
        .value;
  }

  static Future<LslrIndexUnstructured> parse(Stream<String> lines,
      {Uri? fileBaseUrl}) async {
    final entries = <String, List<LslrFileEntry>>{};
    var currentDirectoryPath = ".";
    var currentLevelEntries = <LslrFileEntry>[];

    void finalizeCurrentLevel() {
      if (currentDirectoryPath != null) {
        entries[currentDirectoryPath] = currentLevelEntries;
        currentLevelEntries = <LslrFileEntry>[];
      }
    }

    await for (final line in lines) {
      if (line.endsWith(":")) {
        // New Entry
        finalizeCurrentLevel();
        currentDirectoryPath = line.substring(0, line.length - 1);
      } else if (line.startsWith("total ")) {
        continue;
      } else if (line.isEmpty) {
        continue;
      } else {
        final entry = LslrFileEntry.parse(line);
        currentLevelEntries.add(entry);
      }
    }
    finalizeCurrentLevel();
    return LslrIndexUnstructured(
        fileBaseUrl ?? Uri.parse("http://unknown"), entries);
  }
}

class LslrEntity {
  final Uri fileBaseUrl;
  final String name;
  LslrEntity? parent;
  List<LslrEntity> children;
  LslrFileEntry? fileEntry;
  bool isFile = true;

  LslrEntity(this.fileBaseUrl, this.name) : children = <LslrEntity>[];

  String get fullPath {
    LslrEntity? current = this;
    final parts = <String>[];
    while (current != null) {
      parts.add(current.name);
      current = current.parent;
    }
    return parts.reversed.join("/");
  }

  @override
  String toString() => "LslrEntity(${fullPath})";

  void printFullStructure([String indent = ""]) {
    print("${indent}${name}");
    for (final child in children) {
      child.printFullStructure(indent + "  ");
    }
  }

  void visit(void Function(LslrEntity entity) callback) {
    callback(this);
    for (final child in children) {
      child.visit(callback);
    }
  }

  List<LslrEntity> find(Pattern pattern,
      {bool matchOnFullPath = false, bool exact = false}) {
    final entities = <LslrEntity>[];
    visit((entity) {
      final target = matchOnFullPath ? entity.fullPath : entity.name;

      if (exact) {
        if (target == pattern) {
          entities.add(entity);
        }
      } else {
        if (pattern.allMatches(target).isNotEmpty) {
          entities.add(entity);
        }
      }
    });
    return entities;
  }

  Uri get url {
    if (isFile) {
      return fileBaseUrl.resolve(fullPath);
    } else {
      return fileBaseUrl.resolve(fullPath + "/");
    }
  }
}

class LslrFileEntry {
  final String permissions;
  final int linkCount;
  final String user;
  final String group;
  final int size;
  final String date;
  final String name;

  LslrFileEntry(this.permissions, this.linkCount, this.user, this.group,
      this.size, this.date, this.name);

  factory LslrFileEntry.parse(String line) {
    final splitBySpace = line.split(" ").where((x) => x.isNotEmpty).toList();
    return LslrFileEntry(
        splitBySpace[0],
        int.parse(splitBySpace[1]),
        splitBySpace[2],
        splitBySpace[3],
        int.parse(splitBySpace[4]),
        "${splitBySpace[5]} ${splitBySpace[6]} ${splitBySpace[7]}",
        splitBySpace.skip(8).join(" "));
  }

  @override
  String toString() => "LslrFileEntry(${name})";
}
