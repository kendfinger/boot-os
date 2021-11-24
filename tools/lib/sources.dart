library boot.os.tools.sources;

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

class Sources {
  final Map<String, SourceFile> files;

  Sources(this.files);

  factory Sources.decode(Map<dynamic, dynamic> content) {
    var files = Map<String, SourceFile>();
    for (var key in content.keys) {
      var file = SourceFile.decode(content[key] as Map<dynamic, dynamic>);
      files[key] = file;
    }
    return Sources(files);
  }
}

class SourceFile {
  final String media;
  final String architecture;
  final String format;
  final String version;
  final List<String>? urls;
  final SourceFileAssemble? assemble;
  final SourceFileChecksums checksums;

  SourceFile(this.media, this.architecture, this.format, this.version,
      this.urls, this.assemble, this.checksums);

  factory SourceFile.decode(Map<dynamic, dynamic> content) {
    return SourceFile(
        content["media"],
        content["architecture"],
        content["format"],
        content["version"],
        (content["urls"] as List<dynamic>?)?.cast<String>(),
        content.containsKey("assemble")
            ? SourceFileAssemble.decode(
                content["assemble"] as Map<dynamic, dynamic>)
            : null,
        SourceFileChecksums.decode(
            content["checksums"] as Map<dynamic, dynamic>));
  }
}

class ChecksumWithHash {
  final String checksum;
  final crypto.Hash hash;

  ChecksumWithHash(this.checksum, this.hash);
}

class SourceFileChecksums {
  final String? sha256;
  final String? sha512;

  SourceFileChecksums(this.sha256, this.sha512);

  factory SourceFileChecksums.decode(Map<dynamic, dynamic> content) {
    return SourceFileChecksums(content["sha256"], content["sha512"]);
  }

  ChecksumWithHash createPreferredHash() {
    if (sha512 != null) {
      return ChecksumWithHash(sha512!, crypto.sha512);
    }

    if (sha256 != null) {
      return ChecksumWithHash(sha256!, crypto.sha256);
    }

    throw Exception("Recognized hash not found.");
  }
}

class SourceFileAssemble {
  final String type;
  final List<String> urls;
  final SourceFileChecksums checksums;

  SourceFileAssemble(this.type, this.urls, this.checksums);

  factory SourceFileAssemble.decode(Map<dynamic, dynamic> content) {
    return SourceFileAssemble(
        content["type"],
        (content["urls"] as List<dynamic>).cast<String>(),
        SourceFileChecksums.decode(
            content["checksums"] as Map<dynamic, dynamic>));
  }
}

extension FileChecksumValidate on SourceFileChecksums {
  Future<bool> validatePreferredHash(File file,
      {bool shouldThrowError = true}) async {
    final checksumAndHash = createPreferredHash();
    final stream = file.openRead();
    final digest = await checksumAndHash.hash.bind(stream).single;
    if (digest.toString() != checksumAndHash.checksum) {
      if (shouldThrowError) {
        throw Exception(
            "${file.path} has checksum ${digest.toString()} but ${checksumAndHash.checksum} was expected");
      }
      return false;
    }
    return true;
  }
}
