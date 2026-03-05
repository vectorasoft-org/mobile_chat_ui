import 'image_resolver.dart';

/// Mock resolver delegates to real resolver behavior without GetX dependencies.
class MockImageResolver extends RealImageResolver {
  MockImageResolver({super.chatService});
}
