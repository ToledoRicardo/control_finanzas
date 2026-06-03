import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class BackupService {
  static final BackupService instance = BackupService._init();
  BackupService._init();

  // Obtener directorio de backups
  Future<Directory> getBackupsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(path.join(directory.path, 'WealthVault_Backups'));
    
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }
    
    return backupsDir;
  }

  // Exportar base de datos a un archivo (copia binaria)
  Future<String> exportDatabase() async {
    try {
      // Obtener la base de datos actual
      final db = await DatabaseHelper.instance.database;
      final dbPath = db.path;
      
      // Obtener directorio de backups
      final backupsDir = await getBackupsDirectory();
      
      // Crear nombre de archivo con timestamp
      final now = DateTime.now();
      final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
                       '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final backupFileName = 'control_finanzas_backup_$timestamp.db';
      final backupPath = path.join(backupsDir.path, backupFileName);
      
      // Copiar archivo de base de datos
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        throw Exception('El archivo de base de datos no existe');
      }
      
      final backupFile = await dbFile.copy(backupPath);
      
      // Verificar que el backup se creó correctamente
      if (await backupFile.exists()) {
        return backupPath;
      } else {
        throw Exception('No se pudo crear el archivo de backup');
      }
    } catch (e) {
      throw Exception('Error al exportar base de datos: $e');
    }
  }

  // Exportar base de datos como SQL a carpeta seleccionada por el usuario
  Future<String?> exportDatabaseAsSQL({String? customPath}) async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // Crear nombre de archivo con timestamp
      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
                       '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final backupFileName = 'control_finanzas_$timestamp.sql';
      
      // Generar SQL completo
      final sqlContent = StringBuffer();
      sqlContent.writeln('-- Control Finanzas - Backup Completo');
      sqlContent.writeln('-- Fecha: ${now.toIso8601String()}');
      sqlContent.writeln('-- Versión DB: ${await db.getVersion()}');
      sqlContent.writeln();
      
      // Obtener todas las tablas
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'"
      );
      
      for (var table in tables) {
        final tableName = table['name'] as String;
        final quotedTable = _quoteIdentifier(tableName);
        sqlContent.writeln('-- Tabla: $tableName');
        
        // Obtener estructura de la tabla
        final tableInfo = await db.rawQuery('PRAGMA table_info($quotedTable)');
        sqlContent.writeln('CREATE TABLE IF NOT EXISTS $quotedTable (');
        
        final columns = tableInfo.map((col) {
          final name = col['name'];
          final type = col['type'];
          final notNull = col['notnull'] == 1 ? ' NOT NULL' : '';
          final pk = col['pk'] == 1 ? ' PRIMARY KEY' : '';
          final quotedName = _quoteIdentifier(name.toString());
          return '  $quotedName $type$notNull$pk';
        }).join(',\n');
        
        sqlContent.writeln(columns);
        sqlContent.writeln(');');
        sqlContent.writeln();
        
        // Obtener datos
        final rows = await db.query(tableName);
        if (rows.isNotEmpty) {
          sqlContent.writeln('-- Datos de $tableName (${rows.length} registros)');
          for (var row in rows) {
            final columns = row.keys.map((key) => _quoteIdentifier(key)).join(', ');
            final values = row.values.map((v) {
              if (v == null) return 'NULL';
              if (v is String) return "'${v.replaceAll("'", "''")}'";
              return v.toString();
            }).join(', ');
            sqlContent.writeln('INSERT INTO $quotedTable ($columns) VALUES ($values);');
          }
          sqlContent.writeln();
        }
      }
      
      final sqlBytes = Uint8List.fromList(utf8.encode(sqlContent.toString()));

      String? savePath;
      if (customPath != null) {
        savePath = customPath.toLowerCase().endsWith('.sql')
            ? customPath
            : path.join(customPath, backupFileName);

        final file = File(savePath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(sqlBytes, flush: true);

        if (!await file.exists()) {
          throw Exception('No se pudo crear el archivo SQL');
        }
      } else {
        // En Android/iOS se requieren bytes para guardar con el selector nativo
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Selecciona dónde guardar el backup',
          fileName: backupFileName,
          type: FileType.custom,
          allowedExtensions: ['sql'],
          bytes: sqlBytes,
        );

        if (savePath == null) {
          return null; // Usuario canceló
        }
      }

      return savePath;
    } catch (e) {
      throw Exception('Error al exportar SQL: $e');
    }
  }

  // Importar base de datos desde un archivo
  Future<bool> importDatabase(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      
      // Verificar que el archivo existe
      if (!await backupFile.exists()) {
        throw Exception('El archivo de backup no existe');
      }
      
      // Cerrar la base de datos actual
      final db = await DatabaseHelper.instance.database;
      final dbPath = db.path;
      await DatabaseHelper.instance.closeDatabase();

      final walFile = File('$dbPath-wal');
      final shmFile = File('$dbPath-shm');
      if (await walFile.exists()) {
        await walFile.delete();
      }
      if (await shmFile.exists()) {
        await shmFile.delete();
      }
      
      final targetDbFile = File(dbPath);
      if (await targetDbFile.exists()) {
        await targetDbFile.delete();
      }

      // Reemplazar la base de datos actual con el backup
      await backupFile.copy(dbPath);
      
      // Reabrir la base de datos
      await DatabaseHelper.instance.reopenDatabase();
      
      return true;
    } catch (e) {
      throw Exception('Error al importar base de datos: $e');
    }
  }

  // Importar desde archivo SQL
  Future<bool> importDatabaseFromSqlFile(String sqlPath) async {
    try {
      final sqlFile = File(sqlPath);
      if (!await sqlFile.exists()) {
        throw Exception('El archivo SQL no existe');
      }
      final script = await sqlFile.readAsString();
      return await importDatabaseFromSqlContent(script);
    } catch (e) {
      throw Exception('Error al importar SQL: $e');
    }
  }

  Future<bool> importDatabaseFromSqlContent(String script) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final statements = _splitSqlStatements(script);
      final currentVersion = await db.getVersion();

      await db.transaction((txn) async {
        await txn.execute('PRAGMA foreign_keys=OFF;');

        final tables = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
        );
        for (final table in tables) {
          final tableName = table['name'] as String?;
          if (tableName != null && tableName.isNotEmpty) {
            final quotedTable = _quoteIdentifier(tableName);
            await txn.execute('DROP TABLE IF EXISTS $quotedTable');
          }
        }

        for (final statement in statements) {
          await txn.execute(statement);
        }

        await txn.execute('PRAGMA foreign_keys=ON;');
        await txn.execute('PRAGMA user_version=$currentVersion;');
      });

      await DatabaseHelper.instance.reopenDatabase();

      return true;
    } catch (e) {
      throw Exception('Error al importar SQL: $e');
    }
  }

  // Importar desde archivo seleccionado por el usuario
  Future<bool> importDatabaseFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Selecciona el archivo de backup',
        type: FileType.custom,
        allowedExtensions: ['db', 'sql'],
        withData: true,
      );
      
      if (result == null || result.files.isEmpty) {
        return false; // Usuario canceló
      }
      
      final pickedFile = result.files.single;
      final filePath = pickedFile.path;
      final fileName = pickedFile.name;
      final bytes = pickedFile.bytes;
      final extensionSource = fileName.isNotEmpty ? fileName : (filePath ?? '');
      final extension = path.extension(extensionSource).toLowerCase();

      if (extension == '.sql') {
        if (bytes != null) {
          final script = utf8.decode(bytes);
          return await importDatabaseFromSqlContent(script);
        }
        if (filePath != null) {
          return await importDatabaseFromSqlFile(filePath);
        }
        throw Exception('No se pudo leer el archivo SQL');
      }

      if (bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final tempPath = path.join(
          tempDir.path,
          'import_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(bytes, flush: true);
        return await importDatabase(tempPath);
      }

      if (filePath != null) {
        return await importDatabase(filePath);
      }

      throw Exception('No se pudo leer el archivo de backup');
    } catch (e) {
      throw Exception('Error al importar: $e');
    }
  }

  String _quoteIdentifier(String name) {
    final escaped = name.replaceAll('"', '""');
    return '"$escaped"';
  }

  List<String> _splitSqlStatements(String script) {
    final cleaned = script
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');

    final statements = <String>[];
    final buffer = StringBuffer();
    var inSingleQuote = false;

    for (var i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];

      if (char == "'") {
        if (inSingleQuote) {
          final nextIsQuote = i + 1 < cleaned.length && cleaned[i + 1] == "'";
          if (nextIsQuote) {
            buffer.write("''");
            i++;
            continue;
          }
          inSingleQuote = false;
        } else {
          inSingleQuote = true;
        }
      }

      if (char == ';' && !inSingleQuote) {
        final statement = buffer.toString().trim();
        if (statement.isNotEmpty) {
          statements.add(statement);
        }
        buffer.clear();
        continue;
      }

      buffer.write(char);
    }

    final lastStatement = buffer.toString().trim();
    if (lastStatement.isNotEmpty) {
      statements.add(lastStatement);
    }

    return statements;
  }

  // Obtener lista de backups disponibles
  Future<List<FileSystemEntity>> getBackupFiles() async {
    try {
      final backupsDir = await getBackupsDirectory();
      
      if (!await backupsDir.exists()) {
        return [];
      }
      
      final files = backupsDir.listSync()
          .where((file) => file is File && file.path.endsWith('.db'))
          .toList();
      
      // Ordenar por fecha de modificación (más reciente primero)
      files.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });
      
      return files;
    } catch (e) {
      return [];
    }
  }

  // Eliminar un archivo de backup
  Future<bool> deleteBackup(String backupPath) async {
    try {
      final file = File(backupPath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Obtener tamaño del archivo de backup
  Future<int> getBackupSize(String backupPath) async {
    try {
      final file = File(backupPath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  // Formatear tamaño de archivo
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Obtener nombre legible del backup
  String getBackupDisplayName(String backupPath) {
    final fileName = path.basename(backupPath);
    
    try {
      // Formato: wealthvault_backup_2025-11-19_14-30-45.db
      final dateStr = fileName
          .replaceAll('wealthvault_backup_', '')
          .replaceAll('.db', '');
      
      final parts = dateStr.split('_');
      if (parts.length == 2) {
        final datePart = parts[0].split('-');
        final timePart = parts[1].split('-');
        
        if (datePart.length == 3 && timePart.length == 3) {
          return '${datePart[2]}/${datePart[1]}/${datePart[0]} ${timePart[0]}:${timePart[1]}';
        }
      }
      
      return fileName;
    } catch (e) {
      return fileName;
    }
  }

  // Verificar si hay backups disponibles
  Future<bool> hasBackups() async {
    final files = await getBackupFiles();
    return files.isNotEmpty;
  }

  // Obtener el último backup
  Future<String?> getLatestBackup() async {
    final files = await getBackupFiles();
    if (files.isEmpty) return null;
    return files.first.path;
  }
}
