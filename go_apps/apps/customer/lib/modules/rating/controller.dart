import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

class RatingController extends GetxController {
  final JobsRepository repo = Get.find();
  late final Job job;
  final riderStars = 5.obs;
  final merchantStars = 5.obs;
  final tags = <String>{}.obs;
  final comment = ''.obs;
  final sending = false.obs;

  static const tagKeys = ['friendly', 'safe_driving', 'on_time', 'careful', 'clean'];

  @override
  void onInit() {
    super.onInit();
    job = Get.arguments as Job;
  }

  void toggle(String t) => tags.contains(t) ? tags.remove(t) : tags.add(t);

  Future<void> submit() async {
    sending.value = true;
    try {
      await repo.rate(
        job.id,
        RatingInput(
          riderRating: riderStars.value,
          riderTags: tags.toList(),
          comment: comment.value.trim().isEmpty ? null : comment.value.trim(),
          merchantRating: job.service == ServiceType.food ? merchantStars.value : null,
        ),
      );
      Get.back();
      GoErrors.toast('rating.thanks'.tr);
    } catch (e) {
      GoErrors.show(e);
    } finally {
      sending.value = false;
    }
  }
}
