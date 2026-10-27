import 'package:flutter/material.dart';
import 'package:neon_books_app/src/about/app_assets.dart';
import 'package:neon_books_app/src/admin/admin_service.dart';
import 'package:neon_books_app/src/admin/book_form.dart';
import 'package:neon_books_app/src/api/models.dart';
import 'package:neon_books_app/src/api/problems.dart';
import 'package:neon_books_app/src/app/messages.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart'
    show FeignBadRequest, FeignException;
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The beans of [AdminPage].
typedef AdminPageBeans = (
  AdminService,
  BookForm,
  AppAssets,
);

/// The Admin screen: add a book, upload its cover, delete it, read the
/// server's log. The form is checked in the app first (`BookForm`), then
/// by the server, whose field errors (a 400 ProblemDetail) show under the
/// same fields.
class AdminPage extends SpringStatefulWidget<AdminPageBeans> {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends SpringState<AdminPage, AdminPageBeans> {
  static const _fields = ['isbn', 'title', 'author', 'price'];
  final _controllers = {
    for (final field in _fields) field: TextEditingController(),
  };
  var _errors = <String, String>{};
  Book? _added;
  List<String>? _serverLog;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _add() async {
    final (
      admin,
      form,
      _,
    ) = beans;
    final (book, result) = form.bind({
      for (final field in _fields) field: _controllers[field]!.text,
    });
    if (book == null) {
      // Checked in the app: nothing was sent.
      final spring = context.springContext;
      final locale = Localizations.localeOf(context).toString();
      setState(
        () => _errors = {
          for (final error in result.fieldErrors())
            error.field: spring.getMessageFromResolvable(error, locale: locale),
        },
      );
      return;
    }
    try {
      final added = await admin.addBook(book);
      if (!mounted) {
        return;
      }
      setState(() {
        _errors = {};
        _added = added;
      });
      _snack(context.message('admin.added', args: [added.title]));
    } on FeignBadRequest catch (error) {
      // The server said no: its field errors under the fields.
      setState(() => _errors = fieldErrorsOf(error));
    } on Exception catch (error) {
      if (mounted) {
        _snack(errorMessage(context, error));
      }
    }
  }

  Future<void> _uploadCover(Book book) async {
    final (
      admin,
      _,
      assets,
    ) = beans;
    final done = context.message('admin.coverUploaded');
    try {
      await admin.uploadCover(book.isbn, await assets.sampleCoverBytes());
      _snack(done);
    } on Exception catch (error) {
      if (mounted) {
        _snack(errorMessage(context, error));
      }
    }
  }

  Future<void> _delete(Book book) async {
    final (
      admin,
      _,
      _,
    ) = beans;
    final done = context.message('admin.deleted', args: [book.title]);
    try {
      await admin.deleteBook(book.isbn);
      setState(() => _added = null);
      _snack(done);
    } on Exception catch (error) {
      if (mounted) {
        _snack(errorMessage(context, error));
      }
    }
  }

  Future<void> _loadServerLog() async {
    final (
      admin,
      _,
      _,
    ) = beans;
    try {
      final lines = await admin.serverLogs();
      setState(() => _serverLog = lines);
    } on FeignException catch (error) {
      if (mounted) {
        _snack(errorMessage(context, error));
      }
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.of(context);
    final space = theme.space('m');
    final added = _added;
    final serverLog = _serverLog;
    return Scaffold(
      appBar: AppBar(title: Text(context.message('admin.title'))),
      body: ListView(
        padding: EdgeInsets.all(space),
        children: [
          Text(
            context.message('admin.newBook'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final field in _fields) ...[
            SizedBox(height: theme.space('s')),
            TextField(
              key: Key('admin-$field'),
              controller: _controllers[field],
              keyboardType: field == 'price'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: context.message('admin.field.$field'),
                errorText: _errors[field],
              ),
            ),
          ],
          SizedBox(height: space),
          FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(context.message('admin.add')),
          ),
          if (added != null) ...[
            SizedBox(height: space),
            Card(
              child: ListTile(
                title: Text(added.title),
                subtitle: Text(added.isbn),
                trailing: Wrap(
                  children: [
                    IconButton(
                      onPressed: () => _uploadCover(added),
                      tooltip: context.message('admin.uploadCover'),
                      icon: const Icon(Icons.image_outlined),
                    ),
                    IconButton(
                      onPressed: () => _delete(added),
                      tooltip: context.message('admin.delete'),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: space),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.message('admin.serverLog')),
            trailing: IconButton(
              onPressed: _loadServerLog,
              tooltip: context.message('admin.loadServerLog'),
              icon: const Icon(Icons.refresh),
            ),
          ),
          if (serverLog != null)
            for (final line in serverLog)
              Text(line, style: theme.textStyle('code')),
        ],
      ),
    );
  }
}
