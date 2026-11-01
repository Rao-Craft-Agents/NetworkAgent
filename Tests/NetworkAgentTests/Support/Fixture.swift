import Foundation
@testable import NetworkAgent

enum Fixture {
    /// A folder of its own for one test, removed with the process's temporary files.
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("network-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A recipe app's API: what the package is held to writing well, in the guide's own words.
    static let recipes = NetworkAgent.Input(
        name: "RecipeKit", baseURL: "https://api.recipes.example", auth: .bearer,
        endpoints: [
            "POST /v1/session body(Credentials) -> Session as signIn stores token",
            #"GET /v1/recipes?page,per_page,course:Course -> RecipePage as recipes paged "the newest recipes first""#,
            "GET /v1/recipes/{id:Int} -> Recipe as recipe",
            "POST /v1/recipes body(NewRecipe) -> Recipe as createRecipe",
            "DELETE /v1/recipes/{id:Int} as deleteRecipe",
            "POST /v1/photos multipart(photo, caption:String?) -> Photo as uploadPhoto",
        ],
        entities: [
            "Credentials: email String, password String",
            "Session: token String",
            "RecipePage: recipes [Recipe], total Int = 0",
            "Recipe: id Int, title String, minutes Int = 30, course Course?, added Date",
            "Course: starter | main | dessert",
            "NewRecipe: title String, minutes Int",
            "Photo: id String, url URL",
        ],
        coding: .snake)

    /// A Lemmy-like API: a login that stores its JWT, paged posts, a post made from a JSON body, a path parameter,
    /// an upload, snake_case keys and a date format beside ISO 8601.
    static let lemmy = NetworkAgent.Input(
        name: "LemmyKit", baseURL: "https://lemmy.example", auth: .bearer,
        endpoints: [
            #"POST /api/v3/user/login body(Login) -> LoginResponse as login stores token "signs a person in""#,
            #"GET /api/v3/post/list?page,limit,sort:SortType,type_:ListingType,community_id:Int -> GetPostsResponse as posts paged "the posts of a community, or of the instance""#,
            "GET /api/v3/post?id:Int!,comment_id:Int -> PostResponse as post",
            "POST /api/v3/post body(CreatePost) -> PostResponse as createPost",
            "PUT /api/v3/post body(EditPost) -> PostResponse as editPost",
            "GET /api/v3/user/{username}/posts?page,limit -> GetPostsResponse as User.personPosts",
            "DELETE /api/v3/comment/{id:Int} as deleteComment",
            "POST /pictrs/image multipart(images[]) -> UploadImageResponse as uploadImage",
        ],
        entities: [
            "Login: usernameOrEmail String, password String, totp2faToken String? @totp_2fa_token",
            "LoginResponse: jwt String?, registrationCreated Bool = false, verifyEmailSent Bool = false",
            "GetPostsResponse: posts [PostView]",
            "PostView: post Post, creator Person, community Community, counts PostAggregates, myVote Int?, saved Bool = false",
            "Post: id Int, name String, url URL?, body String?, creatorID Int, communityID Int, published Date, updated Date?, nsfw Bool = false",
            "Person: id Int, name String, displayName String?, avatar URL?, actorID URL, local Bool",
            "Community: id Int, name String, title String, icon URL?, nsfw Bool = false, visibility CommunityVisibility = .public",
            "CommunityVisibility: public = \"Public\" | localOnly = \"LocalOnly\"",
            "PostAggregates: comments Int, score Int, upvotes Int, downvotes Int",
            "PostResponse: postView PostView",
            "CreatePost: name String, communityID Int, url URL?, body String?, nsfw Bool?",
            "EditPost: postID Int, name String?, body String?",
            #"SortType: active = "Active" | hot = "Hot" | new = "New" | topDay = "TopDay""#,
            #"ListingType: all = "All" | local = "Local" | subscribed = "Subscribed""#,
            "UploadImageResponse: msg String, files [ImageFile]?, url URL?",
            "ImageFile: file String, deleteToken String",
        ],
        coding: .snake, dates: ["yyyy-MM-dd HH:mm:ss"])

    /// A Mastodon-like API: an OAuth token, snake_case keys, bearer auth, timelines paged by `max_id` and the `Link`
    /// header, a status made from a JSON body, an upload, a search.
    static let mastodon = NetworkAgent.Input(
        name: "MastodonKit", baseURL: "https://mastodon.example", auth: .bearer,
        endpoints: [
            "POST /oauth/token body(TokenRequest) -> Token as Auth.token stores token(accessToken)",
            "GET /api/v1/accounts/verify_credentials -> Account as Accounts.me",
            "GET /api/v1/accounts/{id}/statuses?limit,max_id,only_media:Bool,exclude_replies:Bool -> [Status] as Accounts.statuses paged",
            #"GET /api/v1/timelines/home?max_id,limit -> [Status] as homeTimeline paged "the signed-in account's home timeline""#,
            "GET /api/v1/statuses/{id} -> Status as status",
            "POST /api/v1/statuses body(NewStatus) -> Status as postStatus",
            "POST /api/v1/statuses/{id}/favourite -> Status as favourite",
            "DELETE /api/v1/statuses/{id} as deleteStatus",
            "POST /api/v2/media multipart(file, description:String?) -> MediaAttachment as uploadMedia",
            "GET /api/v2/search?q!,type:SearchType,limit -> SearchResults as search",
        ],
        entities: [
            #"TokenRequest: grantType String = "password", clientID String, clientSecret String, username String, password String, scope String = "read write""#,
            "Token: accessToken String, tokenType String, scope String, createdAt Int",
            "Account: id String, username String, acct String, displayName String, avatar URL, header URL?, note String, followersCount Int, followingCount Int, statusesCount Int, createdAt Date, bot Bool = false",
            "Status: id String, uri String, url URL?, createdAt Date, account Account, content String, visibility Visibility, sensitive Bool, spoilerText String, mediaAttachments [MediaAttachment], repliesCount Int, reblogsCount Int, favouritesCount Int, favourited Bool?, reblog Status?",
            "MediaAttachment: id String, type MediaType, url URL, previewURL URL?, description String?",
            "MediaType: image | video | gifv | audio | unknown",
            "Visibility: public | unlisted | private | direct",
            "NewStatus: status String, inReplyToID String?, sensitive Bool = false, spoilerText String?, visibility Visibility = .public, mediaIDs [String] = []",
            "SearchResults: accounts [Account], statuses [Status], hashtags [Tag]",
            "Tag: name String, url URL",
            "SearchType: accounts | hashtags | statuses",
        ],
        paging: .cursor, coding: .snake)

    /// RSS, Atom and JSON Feed, read by one client.
    static let news = NetworkAgent.Input(name: "NewsKit", baseURL: "https://news.example", feeds: true)

    /// An IPFS-like API: a multipart upload, a query with a hyphen, bytes back, basic auth and UpperCamel keys.
    static let ipfs = NetworkAgent.Input(
        name: "IPFSKit", baseURL: "https://ipfs.example:5001", auth: .basic,
        endpoints: [
            #"POST /api/v0/add?pin:Bool,cid-version:Int multipart(file) -> AddResult as add "adds a file and answers its content id""#,
            "POST /api/v0/cat?arg! -> Data as cat",
            "POST /api/v0/pin/add?arg! -> PinResult as pin",
            "POST /api/v0/version -> Version as version",
        ],
        entities: [
            "AddResult: name String @Name, hash String @Hash, size String @Size",
            "PinResult: pins [String] @Pins",
            "Version: version String @Version, commit String @Commit, repo String @Repo",
        ])
}
