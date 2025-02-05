export type CallbackID = string;
export interface BarcodeScannerPlugin {
    prepare(options?: ScanOptions): Promise<void>;
    hideBackground(): Promise<void>;
    showBackground(): Promise<void>;
    startScan(options?: ScanOptions): Promise<ScanResult>;
    startScanning(options?: ScanOptions, callback?: (result: ScanResult, err?: any) => void): Promise<CallbackID>;
    pauseScanning(): Promise<void>;
    resumeScanning(): Promise<void>;
    stopScan(options?: StopScanOptions): Promise<void>;
    checkPermission(options?: CheckPermissionOptions): Promise<CheckPermissionResult>;
    openAppSettings(): Promise<void>;
    enableTorch(): Promise<void>;
    disableTorch(): Promise<void>;
    toggleTorch(): Promise<void>;
    getTorchState(): Promise<TorchStateResult>;
}
declare const _SupportedFormat: {
    /**
     * Android only, UPC_A is part of EAN_13 according to Apple docs
     */
    readonly UPC_A: "UPC_A";
    readonly UPC_E: "UPC_E";
    /**
     * Android only
     */
    readonly UPC_EAN_EXTENSION: "UPC_EAN_EXTENSION";
    readonly EAN_8: "EAN_8";
    readonly EAN_13: "EAN_13";
    readonly CODE_39: "CODE_39";
    /**
     * iOS only
     */
    readonly CODE_39_MOD_43: "CODE_39_MOD_43";
    readonly CODE_93: "CODE_93";
    readonly CODE_128: "CODE_128";
    /**
     * Android only
     */
    readonly CODABAR: "CODABAR";
    readonly ITF: "ITF";
    /**
     * iOS only
     */
    readonly ITF_14: "ITF_14";
    readonly AZTEC: "AZTEC";
    readonly DATA_MATRIX: "DATA_MATRIX";
    /**
     * Android only
     */
    readonly MAXICODE: "MAXICODE";
    readonly PDF_417: "PDF_417";
    readonly QR_CODE: "QR_CODE";
    /**
     * Android only
     */
    readonly RSS_14: "RSS_14";
    /**
     * Android only
     */
    readonly RSS_EXPANDED: "RSS_EXPANDED";
};
export declare const SupportedFormat: {
    /**
     * Android only, UPC_A is part of EAN_13 according to Apple docs
     */
    readonly UPC_A: "UPC_A";
    readonly UPC_E: "UPC_E";
    /**
     * Android only
     */
    readonly UPC_EAN_EXTENSION: "UPC_EAN_EXTENSION";
    readonly EAN_8: "EAN_8";
    readonly EAN_13: "EAN_13";
    readonly CODE_39: "CODE_39";
    /**
     * iOS only
     */
    readonly CODE_39_MOD_43: "CODE_39_MOD_43";
    readonly CODE_93: "CODE_93";
    readonly CODE_128: "CODE_128";
    /**
     * Android only
     */
    readonly CODABAR: "CODABAR";
    readonly ITF: "ITF";
    /**
     * iOS only
     */
    readonly ITF_14: "ITF_14";
    readonly AZTEC: "AZTEC";
    readonly DATA_MATRIX: "DATA_MATRIX";
    /**
     * Android only
     */
    readonly MAXICODE: "MAXICODE";
    readonly PDF_417: "PDF_417";
    readonly QR_CODE: "QR_CODE";
    /**
     * Android only
     */
    readonly RSS_14: "RSS_14";
    /**
     * Android only
     */
    readonly RSS_EXPANDED: "RSS_EXPANDED";
};
export type SupportedFormat = typeof _SupportedFormat[keyof typeof _SupportedFormat];
export declare const CameraDirection: {
    readonly FRONT: "front";
    readonly BACK: "back";
};
export type CameraDirection = typeof CameraDirection[keyof typeof CameraDirection];
export interface ScanOptions {
    /**
     * This parameter can be used to make the scanner only recognize specific types of barcodes.
     *  If `targetedFormats` is _not specified_ or _left empty_, _all types_ of barcodes will be targeted.
     *
     * @since 1.2.0
     */
    targetedFormats?: SupportedFormat[];
    /**
     * This parameter can be used to set the camera direction.
     *
     * @since 2.1.0
     */
    cameraDirection?: CameraDirection;
}
export interface StopScanOptions {
    /**
     * If this is set to `true`, the `startScan` method will resolve.
     * Additionally `hasContent` will be `false`.
     * For more information see: https://github.com/capacitor-community/barcode-scanner/issues/17
     *
     * @default true
     * @since 2.1.0
     */
    resolveScan?: boolean;
}
export type ScanResult = IScanResultWithContent | IScanResultWithoutContent;
export interface IScanResultWithContent {
    /**
     * This indicates whether or not the scan resulted in readable content.
     * When stopping the scan with `resolveScan` set to `true`, for example,
     * this parameter is set to `false`, because no actual content was scanned.
     *
     * @since 1.0.0
     */
    hasContent: true;
    /**
     * This holds the content of the barcode if available.
     *
     * @since 1.0.0
     */
    content: string;
    /**
     * This returns format of scan result.
     *
     * @since 2.1.0
     */
    format: string;
}
export interface IScanResultWithoutContent {
    /**
     * This indicates whether or not the scan resulted in readable content.
     * When stopping the scan with `resolveScan` set to `true`, for example,
     * this parameter is set to `false`, because no actual content was scanned.
     *
     * @since 1.0.0
     */
    hasContent: false;
    /**
     * This holds the content of the barcode if available.
     *
     * @since 1.0.0
     */
    content: undefined;
    /**
     * This returns format of scan result.
     *
     * @since 2.1.0
     */
    format: undefined;
}
export interface CheckPermissionOptions {
    /**
     * If this is set to `true`, the user will be prompted for the permission.
     * The prompt will only show if the permission was not yet granted and also not denied completely yet.
     * For more information see: https://github.com/capacitor-community/barcode-scanner#permissions
     *
     * @default false
     * @since 1.0.0
     */
    force?: boolean;
}
export interface CheckPermissionResult {
    /**
     * When set to `true`, the ermission is granted.
     */
    granted?: boolean;
    /**
     * When set to `true`, the permission is denied and cannot be prompted for.
     * The `openAppSettings` method should be used to let the user grant the permission.
     *
     * @since 1.0.0
     */
    denied?: boolean;
    /**
     * When this is set to `true`, the user was just prompted the permission.
     * Ergo: a dialog, asking the user to grant the permission, was shown.
     *
     * @since 1.0.0
     */
    asked?: boolean;
    /**
     * When this is set to `true`, the user has never been prompted the permission.
     *
     * @since 1.0.0
     */
    neverAsked?: boolean;
    /**
     * iOS only
     * When this is set to `true`, the permission cannot be requested for some reason.
     *
     * @since 1.0.0
     */
    restricted?: boolean;
    /**
     * iOS only
     * When this is set to `true`, the permission status cannot be retrieved.
     *
     * @since 1.0.0
     */
    unknown?: boolean;
}
export interface TorchStateResult {
    /**
     * Whether or not the torch is currently enabled.
     */
    isEnabled: boolean;
}
export {};
