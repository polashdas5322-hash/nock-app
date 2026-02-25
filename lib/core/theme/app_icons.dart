import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Centralized Icon System for Vibe
///
/// Enforces consistency by mapping abstract concepts to specific icon libraries.
/// primary: Phosphor Icons (Custom/Premium/Noir feel)
/// fallback: Material Icons (System/Utility)
class AppIcons {
  AppIcons._();

  // Navigation / Actions
  static PhosphorIconData get close =>
      PhosphorIcons.x(PhosphorIconsStyle.light);
  static PhosphorIconData get back =>
      PhosphorIcons.arrowLeft(PhosphorIconsStyle.light);
  static PhosphorIconData get menu =>
      PhosphorIcons.list(PhosphorIconsStyle.light);
  static PhosphorIconData get undo =>
      PhosphorIcons.arrowCounterClockwise(PhosphorIconsStyle.light);
  static PhosphorIconData get search =>
      PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.light);
  static PhosphorIconData get moreVertical =>
      PhosphorIcons.dotsThreeVertical(PhosphorIconsStyle.light);
  static PhosphorIconData get moreHorizontal =>
      PhosphorIcons.dotsThree(PhosphorIconsStyle.light);

  // Social / Squad
  static PhosphorIconData get friends =>
      PhosphorIcons.users(PhosphorIconsStyle.light);
  static PhosphorIconData get addFriend =>
      PhosphorIcons.userPlus(PhosphorIconsStyle.light);
  static PhosphorIconData get chat =>
      PhosphorIcons.chatCircle(PhosphorIconsStyle.light);
  static PhosphorIconData get share =>
      PhosphorIcons.shareNetwork(PhosphorIconsStyle.light);
  static PhosphorIconData get profile =>
      PhosphorIcons.userCircle(PhosphorIconsStyle.light);

  // Camera / Media
  static PhosphorIconData get camera =>
      PhosphorIcons.camera(PhosphorIconsStyle.light);
  static PhosphorIconData get flashOn =>
      PhosphorIcons.lightning(PhosphorIconsStyle.fill); // Filled for state
  static PhosphorIconData get flashOff =>
      PhosphorIcons.lightningSlash(PhosphorIconsStyle.light);
  static PhosphorIconData get flashAuto =>
      PhosphorIcons.lightning(PhosphorIconsStyle.light);
  static PhosphorIconData get switchCamera =>
      PhosphorIcons.cameraRotate(PhosphorIconsStyle.light);
  static PhosphorIconData get shutter =>
      PhosphorIcons.circle(PhosphorIconsStyle.light);
  static PhosphorIconData get video =>
      PhosphorIcons.videoCamera(PhosphorIconsStyle.light);
  static PhosphorIconData get gallery =>
      PhosphorIcons.image(PhosphorIconsStyle.light);
  static PhosphorIconData get mic =>
      PhosphorIcons.microphone(PhosphorIconsStyle.light);
  static PhosphorIconData get play =>
      PhosphorIcons.play(PhosphorIconsStyle.fill);
  static PhosphorIconData get pause =>
      PhosphorIcons.pause(PhosphorIconsStyle.fill);

  // Vibe / Feelings
  static PhosphorIconData get vibe =>
      PhosphorIcons.sparkle(PhosphorIconsStyle.light);
  static PhosphorIconData get like =>
      PhosphorIcons.heart(PhosphorIconsStyle.light);
  static PhosphorIconData get reply =>
      PhosphorIcons.arrowBendUpLeft(PhosphorIconsStyle.light);
  static PhosphorIconData get send =>
      PhosphorIcons.paperPlaneRight(PhosphorIconsStyle.light);

  // Tools / Editing
  static PhosphorIconData get text =>
      PhosphorIcons.textT(PhosphorIconsStyle.light);
  static PhosphorIconData get draw =>
      PhosphorIcons.pencilSimple(PhosphorIconsStyle.light);
  static PhosphorIconData get sticker =>
      PhosphorIcons.sticker(PhosphorIconsStyle.light);
  static PhosphorIconData get save =>
      PhosphorIcons.downloadSimple(PhosphorIconsStyle.light);
  static PhosphorIconData get delete =>
      PhosphorIcons.trash(PhosphorIconsStyle.light);

  // Subscription / Premium
  static PhosphorIconData get crown =>
      PhosphorIcons.crown(PhosphorIconsStyle.light);
  static PhosphorIconData get lock =>
      PhosphorIcons.lock(PhosphorIconsStyle.light);
  static PhosphorIconData get unlock =>
      PhosphorIcons.lockOpen(PhosphorIconsStyle.light);

  // Feedback
  static PhosphorIconData get check =>
      PhosphorIcons.check(PhosphorIconsStyle.light);
  static PhosphorIconData get error =>
      PhosphorIcons.warningCircle(PhosphorIconsStyle.light);
  static PhosphorIconData get info =>
      PhosphorIcons.info(PhosphorIconsStyle.light);

  static PhosphorIconData get edit =>
      PhosphorIcons.pencilSimple(PhosphorIconsStyle.light);
  static PhosphorIconData get notification =>
      PhosphorIcons.bell(PhosphorIconsStyle.light);
  static PhosphorIconData get widget =>
      PhosphorIcons.squaresFour(PhosphorIconsStyle.light);
  static PhosphorIconData get help =>
      PhosphorIcons.question(PhosphorIconsStyle.light);
  static PhosphorIconData get block =>
      PhosphorIcons.prohibit(PhosphorIconsStyle.light);
  static PhosphorIconData get removeFriend =>
      PhosphorIcons.userMinus(PhosphorIconsStyle.light);
  static PhosphorIconData get chevronRight =>
      PhosphorIcons.caretRight(PhosphorIconsStyle.light);
  static PhosphorIconData get grid =>
      PhosphorIcons.squaresFour(PhosphorIconsStyle.light);
  static PhosphorIconData get brokenImage =>
      PhosphorIcons.warningCircle(PhosphorIconsStyle.light);
  static PhosphorIconData get contacts =>
      PhosphorIcons.addressBook(PhosphorIconsStyle.light);
  static PhosphorIconData get history =>
      PhosphorIcons.clockCounterClockwise(PhosphorIconsStyle.light);
  static PhosphorIconData get verified =>
      PhosphorIcons.shieldCheck(PhosphorIconsStyle.light);
  static PhosphorIconData get sparkle =>
      PhosphorIcons.sparkle(PhosphorIconsStyle.light);
  static PhosphorIconData get arrowLeft =>
      PhosphorIcons.arrowLeft(PhosphorIconsStyle.light);
  static PhosphorIconData get arrowRight =>
      PhosphorIcons.arrowRight(PhosphorIconsStyle.light);
  static PhosphorIconData get caretLeft =>
      PhosphorIcons.caretLeft(PhosphorIconsStyle.light);
  static PhosphorIconData get caretRight =>
      PhosphorIcons.caretRight(PhosphorIconsStyle.light);
  static PhosphorIconData get caretUp =>
      PhosphorIcons.caretUp(PhosphorIconsStyle.light);
  static PhosphorIconData get caretDown =>
      PhosphorIcons.caretDown(PhosphorIconsStyle.light);
  static PhosphorIconData get dotsThree =>
      PhosphorIcons.dotsThree(PhosphorIconsStyle.light);
  static PhosphorIconData get dotsThreeVertical =>
      PhosphorIcons.dotsThreeVertical(PhosphorIconsStyle.light);
  static PhosphorIconData get qrCode =>
      PhosphorIcons.qrCode(PhosphorIconsStyle.light);
  static PhosphorIconData get scan =>
      PhosphorIcons.scan(PhosphorIconsStyle.light);
  static PhosphorIconData get privacy =>
      PhosphorIcons.shieldCheck(PhosphorIconsStyle.light);
  static PhosphorIconData get volumeUp =>
      PhosphorIcons.speakerHigh(PhosphorIconsStyle.light);
  static PhosphorIconData get touch =>
      PhosphorIcons.handTap(PhosphorIconsStyle.light);
  static PhosphorIconData get circle =>
      PhosphorIcons.circle(PhosphorIconsStyle.light);
  static PhosphorIconData get checkCircle =>
      PhosphorIcons.checkCircle(PhosphorIconsStyle.light);
  static PhosphorIconData get music =>
      PhosphorIcons.musicNote(PhosphorIconsStyle.light);
  static PhosphorIconData get sync =>
      PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.light);
  static PhosphorIconData get closedCaption =>
      PhosphorIcons.subtitles(PhosphorIconsStyle.light);
  static PhosphorIconData get trash =>
      PhosphorIcons.trash(PhosphorIconsStyle.light);
  static PhosphorIconData get flag =>
      PhosphorIcons.flag(PhosphorIconsStyle.light);
  static PhosphorIconData get hourglass =>
      PhosphorIcons.hourglassHigh(PhosphorIconsStyle.light);
  static PhosphorIconData get textSnippet =>
      PhosphorIcons.article(PhosphorIconsStyle.light);
  static PhosphorIconData get peopleAlt =>
      PhosphorIcons.usersThree(PhosphorIconsStyle.light);
  static PhosphorIconData get exploreOff =>
      PhosphorIcons.compass(PhosphorIconsStyle.light);
  static PhosphorIconData get snapchat =>
      PhosphorIcons.ghost(PhosphorIconsStyle.light);
  static PhosphorIconData get messenger =>
      PhosphorIcons.messengerLogo(PhosphorIconsStyle.light);
  static PhosphorIconData get telegram =>
      PhosphorIcons.telegramLogo(PhosphorIconsStyle.light);
  static PhosphorIconData get sms =>
      PhosphorIcons.chatTeardropText(PhosphorIconsStyle.light);
  static PhosphorIconData get apple =>
      PhosphorIcons.appleLogo(PhosphorIconsStyle.light);
  static PhosphorIconData get google =>
      PhosphorIcons.googleLogo(PhosphorIconsStyle.light);
}
