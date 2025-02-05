import { WebPlugin } from '@capacitor/core';
import { BarcodeFormat, BrowserQRCodeReader } from '@zxing/browser';
import { DecodeHintType } from '@zxing/library';
import { CameraDirection, } from './definitions';
class BarcodeScannerWeb extends WebPlugin {
    constructor() {
        super(...arguments);
        this._formats = [];
        this._controls = null;
        this._torchState = false;
        this._video = null;
        this._options = null;
        this._backgroundColor = null;
        this._facingMode = BarcodeScannerWeb._BACK;
    }
    async prepare() {
        await this._getVideoElement();
        return;
    }
    async hideBackground() {
        this._backgroundColor = document.documentElement.style.backgroundColor;
        document.documentElement.style.backgroundColor = 'transparent';
        return;
    }
    async showBackground() {
        document.documentElement.style.backgroundColor = this._backgroundColor || '';
        return;
    }
    async startScan(_options) {
        var _a;
        this._options = _options;
        this._formats = [];
        (_a = _options === null || _options === void 0 ? void 0 : _options.targetedFormats) === null || _a === void 0 ? void 0 : _a.forEach((format) => {
            const formatIndex = Object.keys(BarcodeFormat).indexOf(format);
            if (formatIndex >= 0) {
                this._formats.push(0);
            }
            else {
                console.error(format, 'is not supported on web');
            }
        });
        if (!!(_options === null || _options === void 0 ? void 0 : _options.cameraDirection)) {
            this._facingMode = _options.cameraDirection === CameraDirection.BACK ? BarcodeScannerWeb._BACK : BarcodeScannerWeb._FORWARD;
        }
        const video = await this._getVideoElement();
        if (video) {
            return await this._getFirstResultFromReader();
        }
        else {
            throw this.unavailable('Missing video element');
        }
    }
    async startScanning(_options, _callback) {
        throw this.unimplemented('Not implemented on web.');
    }
    async pauseScanning() {
        if (this._controls) {
            this._controls.stop();
            this._controls = null;
        }
    }
    async resumeScanning() {
        this._getFirstResultFromReader();
    }
    async stopScan(_options) {
        this._stop();
        if (this._controls) {
            this._controls.stop();
            this._controls = null;
        }
    }
    async checkPermission(_options) {
        if (typeof navigator === 'undefined' || !navigator.permissions) {
            throw this.unavailable('Permissions API not available in this browser');
        }
        try {
            // https://developer.mozilla.org/en-US/docs/Web/API/Permissions/query
            // the specific permissions that are supported varies among browsers that implement the
            // permissions API, so we need a try/catch in case 'camera' is invalid
            const permission = await window.navigator.permissions.query({
                name: 'camera',
            });
            if (permission.state === 'prompt') {
                return {
                    neverAsked: true,
                };
            }
            if (permission.state === 'denied') {
                return {
                    denied: true,
                };
            }
            if (permission.state === 'granted') {
                return {
                    granted: true,
                };
            }
            return {
                unknown: true,
            };
        }
        catch (_a) {
            throw this.unavailable('Camera permissions are not available in this browser');
        }
    }
    async openAppSettings() {
        throw this.unavailable('App settings are not available in this browser');
    }
    async disableTorch() {
        if (this._controls && this._controls.switchTorch) {
            this._controls.switchTorch(false);
            this._torchState = false;
        }
    }
    async enableTorch() {
        if (this._controls && this._controls.switchTorch) {
            this._controls.switchTorch(true);
            this._torchState = true;
        }
    }
    async toggleTorch() {
        if (this._controls && this._controls.switchTorch) {
            this._controls.switchTorch(true);
        }
    }
    async getTorchState() {
        return { isEnabled: this._torchState };
    }
    async _getVideoElement() {
        if (!this._video) {
            await this._startVideo();
        }
        return this._video;
    }
    async _getFirstResultFromReader() {
        const videoElement = await this._getVideoElement();
        return new Promise(async (resolve) => {
            if (videoElement) {
                let hints;
                if (this._formats.length) {
                    hints = new Map();
                    hints.set(DecodeHintType.POSSIBLE_FORMATS, this._formats);
                }
                const reader = new BrowserQRCodeReader(hints);
                this._controls = await reader.decodeFromVideoElement(videoElement, (result, error, controls) => {
                    if (!error && result && result.getText()) {
                        resolve({
                            hasContent: true,
                            content: result.getText(),
                            format: result.getBarcodeFormat().toString(),
                        });
                        controls.stop();
                        this._controls = null;
                        this._stop();
                    }
                    if (error && error.message) {
                        console.error(error.message);
                    }
                });
            }
        });
    }
    async _startVideo() {
        return new Promise(async (resolve, reject) => {
            var _a;
            await navigator.mediaDevices
                .getUserMedia({
                audio: false,
                video: true,
            })
                .then((stream) => {
                // Stop any existing stream so we can request media with different constraints based on user input
                stream.getTracks().forEach((track) => track.stop());
            })
                .catch((error) => {
                reject(error);
            });
            const body = document.body;
            const video = document.getElementById('video');
            if (!video) {
                const parent = document.createElement('div');
                parent.setAttribute('style', 'position:absolute; top: 0; left: 0; width:100%; height: 100%; background-color: black;');
                this._video = document.createElement('video');
                this._video.id = 'video';
                // Don't flip video feed if camera is rear facing
                if (((_a = this._options) === null || _a === void 0 ? void 0 : _a.cameraDirection) !== CameraDirection.BACK) {
                    this._video.setAttribute('style', '-webkit-transform: scaleX(-1); transform: scaleX(-1); width:100%; height: 100%;');
                }
                else {
                    this._video.setAttribute('style', 'width:100%; height: 100%;');
                }
                const userAgent = navigator.userAgent.toLowerCase();
                const isSafari = userAgent.includes('safari') && !userAgent.includes('chrome');
                // Safari on iOS needs to have the autoplay, muted and playsinline attributes set for video.play() to be successful
                // Without these attributes this.video.play() will throw a NotAllowedError
                // https://developer.apple.com/documentation/webkit/delivering_video_content_for_safari
                if (isSafari) {
                    this._video.setAttribute('autoplay', 'true');
                    this._video.setAttribute('muted', 'true');
                    this._video.setAttribute('playsinline', 'true');
                }
                parent.appendChild(this._video);
                body.appendChild(parent);
                if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
                    const constraints = {
                        video: this._facingMode,
                    };
                    navigator.mediaDevices.getUserMedia(constraints).then((stream) => {
                        //video.src = window.URL.createObjectURL(stream);
                        if (this._video) {
                            this._video.srcObject = stream;
                            this._video.play();
                        }
                        resolve({});
                    }, (err) => {
                        reject(err);
                    });
                }
            }
            else {
                reject({ message: 'camera already started' });
            }
        });
    }
    async _stop() {
        var _a;
        if (this._video) {
            this._video.pause();
            const st = this._video.srcObject;
            const tracks = st.getTracks();
            for (var i = 0; i < tracks.length; i++) {
                var track = tracks[i];
                track.stop();
            }
            (_a = this._video.parentElement) === null || _a === void 0 ? void 0 : _a.remove();
            this._video = null;
        }
    }
}
BarcodeScannerWeb._FORWARD = { facingMode: 'user' };
BarcodeScannerWeb._BACK = { facingMode: 'environment' };
export { BarcodeScannerWeb };
//# sourceMappingURL=web.js.map