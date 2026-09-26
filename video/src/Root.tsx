import { Composition, Folder } from "remotion";
import { FPS, totalFrames } from "./config";
import { Showcase } from "./Showcase";

// 1080 x 1920 for Reels, TikTok and Shorts; 886 x 1920 is the App Store app preview size for 6.1"-6.9" iPhones.
export const RemotionRoot: React.FC = () => (
  <>
    <Folder name="Social">
      <Composition id="Social-en" component={Showcase} durationInFrames={totalFrames("social")} fps={FPS} width={1080} height={1920} defaultProps={{ lang: "en", variant: "social", music: true }} />
      <Composition id="Social-no" component={Showcase} durationInFrames={totalFrames("social")} fps={FPS} width={1080} height={1920} defaultProps={{ lang: "no", variant: "social", music: true }} />
    </Folder>
    <Folder name="AppStore">
      <Composition id="AppStore-en" component={Showcase} durationInFrames={totalFrames("appstore")} fps={FPS} width={886} height={1920} defaultProps={{ lang: "en", variant: "appstore", music: true }} />
      <Composition id="AppStore-no" component={Showcase} durationInFrames={totalFrames("appstore")} fps={FPS} width={886} height={1920} defaultProps={{ lang: "no", variant: "appstore", music: true }} />
    </Folder>
  </>
);
