# Immich SwiftUI — DTO & API Field Reference (authoritative, for implementer)

Dual-sourced: server Zod schemas + Dart models. GitHub `immich-app/immich` main branch.

## Enum values
- AssetType `type`: `"IMAGE"|"VIDEO"|"AUDIO"|"OTHER"`
- AssetVisibility `visibility`: `"archive"|"timeline"|"hidden"|"locked"`
- AssetOrder `order`: `"asc"|"desc"`
- AssetOrderBy `orderBy`: `"takenAt"|"createdAt"`
- Thumbnail `size`: `"thumbnail"|"preview"|"fullsize"`
- AssetMedia status: `"created"|"duplicate"`
- BulkUpload action: `"accept"|"reject"`, reason: `"duplicate"|"unsupported-format"`

## Date format
ISO 8601 `yyyy-MM-dd'T'HH:mm:ss.SSSZ` everywhere (server `date.toISOString()`), UTC + 3-digit ms.
EXCEPTION: `timeBucket` values are plain `YYYY-MM-DD`. Swift: `ISO8601DateFormatter` with `.withFractionalSeconds`+`.withInternetDateTime`.

## DTOs

### LoginCredentialDto (req POST /api/auth/login)
`email:String, password:String`

### LoginResponseDto (201)
`accessToken:String, userId:String, userEmail:String, name:String, profileImagePath:String, isAdmin:Bool, shouldChangePassword:Bool, isOnboarded:Bool`

### LogoutResponseDto (200, POST /api/auth/logout)
`successful:Bool, redirectUri:String`

### ServerPingResponse (200 GET /api/server/ping) — JSON, not text
`res:String` (== "pong")

### ServerVersionResponseDto
`major:Int, minor:Int, patch:Int, prerelease:Int?`

### ServerConfigDto
`oauthButtonText,loginPageMessage:String; trashDays,userDeleteDelay:Int; isInitialized,isOnboarded:Bool; externalDomain,mapDarkStyleUrl,mapLightStyleUrl:String; publicUsers,maintenanceMode:Bool; minFaces:Int`

### ValidateAccessTokenResponseDto (POST /api/auth/validateToken)
`authStatus:Bool`

### TimeBucketsResponseDto (GET /api/timeline/buckets → [{...}])
`timeBucket:String` (YYYY-MM-DD), `count:Int`

### TimeBucketAssetResponseDto (GET /api/timeline/bucket?timeBucket=... → COLUMNAR) ⚠ FM-1
14 REQUIRED parallel arrays (zipped by index):
`id:[String], ownerId:[String], ratio:[Double], isFavorite:[Bool], visibility:[String], isTrashed:[Bool], isImage:[Bool], thumbhash:[String?], createdAt:[String], fileCreatedAt:[String], localOffsetHours:[Double], duration:[Int?], livePhotoVideoId:[String?], projectionType:[String?]`
5 OPTIONAL arrays (may be absent): `stack:[[String?]?]?`, `city:[String?]?`, `country:[String?]?`, `latitude:[Double?]?`, `longitude:[Double?]?`

### AssetResponseDto (GET /api/assets/:id)
Required(22): `id,type:String, thumbhash:String?, localDateTime:String, duration:Int?, hasMetadata:Bool, width:Int?, height:Int?, createdAt:String, ownerId:String, originalPath:String, originalFileName:String, fileCreatedAt:String, fileModifiedAt:String, updatedAt:String, isFavorite:Bool, isArchived:Bool, isTrashed:Bool, isOffline:Bool, visibility:String, checksum:String, isEdited:Bool`
Optional: `originalMimeType:String?, livePhotoVideoId:String?, owner:UserResponseDto?, libraryId:String?, exifInfo:ExifResponseDto?, tags:[TagResponseDto]?, people:[PersonResponseDto]?, stack:AssetStackResponseDto?, duplicateId:String?, resized:Bool?`

UserResponseDto: `id,name,email,profileImagePath,avatarColor,profileChangedAt:String` (avatarColor enum: primary|pink|red|yellow|blue|green|purple|orange|gray|amber)
ExifResponseDto (all nullable): make,model,orientation,dateTimeOriginal,modifyDate,timeZone,lensModel,exposureTime,city,state,country,description,projectionType:String?; exifImageWidth,exifImageHeight,fileSizeInByte,iso,rating:Int?; fNumber,focalLength,latitude,longitude:Double?
AssetStackResponseDto: `id,primaryAssetId:String, assetCount:Int`

### AssetMediaResponseDto (upload resp, 201/200)
`id:String, status:String` (created|duplicate)

### AssetMediaCreateDto — multipart POST /api/assets ⚠ ONLY 10 fields
`assetData:Data`(req), `fileCreatedAt:String`(req ISO), `fileModifiedAt:String`(req ISO), `duration:String?`(ms stringified), `filename:String?`, `isFavorite:String`("true"|"false" — STRING not Bool, server stringToBool), `visibility:String?`, `livePhotoVideoId:String?`, `metadata:String?`(JSON array), `sidecarData:Data?`
DO NOT send deviceAssetId/deviceId/isArchived/fileExtension/isOffline/isExternal/isReadOnly/checksum as form fields. Checksum → `x-immich-checksum` HEADER (base64 sha1, or hex).

### AssetBulkUploadCheckDto (POST /api/assets/bulk-upload-check)
req: `assets:[{id:String, checksum:String}]` (checksum base64-or-hex sha1)
resp: `results:[{id:String, action:String(accept|reject), reason:String?, assetId:String?, isTrashed:Bool?}]`

### UpdateAssetDto (PATCH /api/assets/:id — NOT PUT, deprecated)
All optional: `isFavorite:Bool?, visibility:String?, dateTimeOriginal:String?, latitude:Double?, longitude:Double?, rating:Int?(-1|1-5, 0 invalid), description:String?, livePhotoVideoId:String?`

### AssetBulkDeleteDto (DELETE /api/assets → 204)
`ids:[String], force:Bool?`

## Query params
- `/timeline/buckets` (all opt): userId,albumId,personId,tagId,isFavorite,bool-str isTrashed,bool-str withStacked,withPartners(bool-str),order,orderBy,visibility,withCoordinates(bool-str),bbox("w,s,e,n")
- `/timeline/bucket`: `timeBucket` (req, YYYY-MM-DD) + same optional filters. NO pagination. Returns ALL assets for bucket.

## x-immich-checksum header
SHA-1 of file bytes, base64-encoded (server also accepts hex). Used on POST /api/assets + bulk-upload-check (as JSON field). Swift: `CryptoKit.Insecure.SHA1.hash(data:)` → Data → base64.
