import 'dart:async';
import 'dart:io';

/// A simple concrete implementation of [HttpHeaders] for testing.
class FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = {};

  @override
  ContentType? get contentType {
    final header = value(HttpHeaders.contentTypeHeader);
    if (header == null) return null;

    return ContentType.parse(header);
  }

  @override
  void add(
    String name,
    Object value, {
    bool preserveHeaderCase = false,
  }) {
    final key = name.toLowerCase();
    _headers.putIfAbsent(key, () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = [value.toString()];
  }

  @override
  List<String>? operator [](String name) => _headers[name.toLowerCase()];

  @override
  String? value(String name) {
    final values = _headers[name.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.first;
  }

  // Stub out all other members.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fake HTTP client that implements HttpClient.
class FakeHttpClient implements HttpClient {
  FakeHttpClient({
    required this.responseData,
    this.statusCode = 200,
    int? contentLength,
    this.error = const {},
  }) : contentLength = contentLength ?? responseData.length;

  final List<int> responseData;
  final int statusCode;
  final int contentLength;
  final Map<int, Object> error;
  int requestCount = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final error = this.error[requestCount];
    requestCount++;
    if (error != null) {
      return Future.error(error);
    }


    return FakeHttpClientRequest(url, responseData, statusCode, contentLength);
  }

  @override
  void close({bool force = false}) {
    // Nothing to close.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fake HTTP client request.
class FakeHttpClientRequest implements HttpClientRequest {
  final Uri url;
  final List<int> fakeData;
  final int statusCode;

  @override
  final int contentLength;

  @override
  int maxRedirects = 5;

  FakeHttpClientRequest(
      this.url, this.fakeData, this.statusCode, this.contentLength);

  @override
  Future<HttpClientResponse> close() async {
    return FakeHttpClientResponse(fakeData, statusCode, contentLength);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fake HTTP client response that uses a StreamController to send fakeData
/// and then closes the stream.
class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final List<int> fakeData;
  @override
  final int statusCode;
  @override
  final int contentLength;

  FakeHttpClientResponse(this.fakeData, this.statusCode, this.contentLength);

  @override
  HttpHeaders get headers {
    final h = FakeHttpHeaders();
    h.set(HttpHeaders.contentLengthHeader, contentLength);
    h.set(HttpHeaders.acceptRangesHeader, 'bytes');
    h.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
    return h;
  }

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final controller = StreamController<List<int>>();
    // Add fakeData and then close the stream.
    controller.add(fakeData);
    controller.close();
    return controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A Fake HttpOverrides that returns a FakeHttpClient.
class FakeHttpOverrides extends HttpOverrides {
  FakeHttpOverrides(this._client);

  final HttpClient _client;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _client;
  }
}
