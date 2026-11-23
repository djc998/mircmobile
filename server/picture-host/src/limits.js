// Sizes and lifetimes for uploads. Kept out of index.js: the Workers
// runtime treats every named export of the entry module as an entry point,
// and newer versions refuse ones that aren't handlers.

export const MAX_BYTES = 10 * 1024 * 1024;
export const MAX_FILE_BYTES = 25 * 1024 * 1024;
export const EXPIRY_CHOICES = [3600, 14400];
export const DEFAULT_EXPIRY = 14400;
