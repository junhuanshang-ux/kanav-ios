import Foundation

// MARK: - 站点配置

enum Site {
    static let base = "https://jable.tv"

    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 首页横向 chips 上直接露出的常用分类
    static let quickCategories: [Category] = [
        Category(name: "最新", basePath: "/latest-updates/"),
        Category(name: "热门", basePath: "/hot/"),
        Category(name: "中文字幕", basePath: "/categories/chinese-subtitle/"),
        Category(name: "新作", basePath: "/new-release/"),
        Category(name: "無碼解放", basePath: "/categories/uncensored/"),
        Category(name: "制服誘惑", basePath: "/categories/uniform/"),
        Category(name: "巨乳", basePath: "/tags/big-tits/"),
        Category(name: "人妻", basePath: "/tags/wife/")
    ]

    /// 全部分类，按站点导航分组（路径来自 REA 抓取的真实标签树）
    static let categoryGroups: [CategoryGroup] = [
        CategoryGroup(group: "主题", items: [
            Category(name: "中文字幕", basePath: "/categories/chinese-subtitle/"),
            Category(name: "角色劇情", basePath: "/categories/roleplay/"),
            Category(name: "制服誘惑", basePath: "/categories/uniform/"),
            Category(name: "絲襪美腿", basePath: "/categories/pantyhose/"),
            Category(name: "直接開啪", basePath: "/categories/sex-only/"),
            Category(name: "多P群交", basePath: "/categories/groupsex/"),
            Category(name: "主奴調教", basePath: "/categories/bdsm/"),
            Category(name: "男友視角", basePath: "/categories/pov/"),
            Category(name: "凌辱快感", basePath: "/categories/insult/"),
            Category(name: "盜攝偷拍", basePath: "/categories/private-cam/"),
            Category(name: "無碼解放", basePath: "/categories/uncensored/"),
            Category(name: "女同歡愉", basePath: "/categories/lesbian/")
        ]),
        CategoryGroup(group: "排序", items: [
            Category(name: "最新", basePath: "/latest-updates/"),
            Category(name: "熱度", basePath: "/hot/"),
            Category(name: "新作", basePath: "/new-release/")
        ]),
        CategoryGroup(group: "衣著", items: [
            Category(name: "Cosplay", basePath: "/tags/Cosplay/"),
            Category(name: "制服", basePath: "/tags/school-uniform/"),
            Category(name: "絲襪", basePath: "/tags/pantyhose/"),
            Category(name: "黑絲", basePath: "/tags/black-pantyhose/"),
            Category(name: "吊帶襪", basePath: "/tags/stockings/"),
            Category(name: "女僕", basePath: "/tags/maid/"),
            Category(name: "兔女郎", basePath: "/tags/bunny-girl/"),
            Category(name: "和服", basePath: "/tags/kimono/"),
            Category(name: "旗袍", basePath: "/tags/cheongsam/"),
            Category(name: "水着", basePath: "/tags/swimsuit/"),
            Category(name: "婚紗", basePath: "/tags/wedding-dress/"),
            Category(name: "眼鏡娘", basePath: "/tags/glasses/"),
            Category(name: "獸耳", basePath: "/tags/kemonomimi/")
        ]),
        CategoryGroup(group: "身材", items: [
            Category(name: "巨乳", basePath: "/tags/big-tits/"),
            Category(name: "貧乳", basePath: "/tags/small-tits/"),
            Category(name: "美腿", basePath: "/tags/beautiful-leg/"),
            Category(name: "美尻", basePath: "/tags/beautiful-butt/"),
            Category(name: "白虎", basePath: "/tags/hairless-pussy/"),
            Category(name: "熟女", basePath: "/tags/mature-woman/"),
            Category(name: "少女", basePath: "/tags/girl/"),
            Category(name: "嬌小", basePath: "/tags/dainty/"),
            Category(name: "長身", basePath: "/tags/tall/"),
            Category(name: "黑肉", basePath: "/tags/suntan/"),
            Category(name: "短髮", basePath: "/tags/short-hair/"),
            Category(name: "紋身", basePath: "/tags/tattoo/")
        ]),
        CategoryGroup(group: "交合", items: [
            Category(name: "中出", basePath: "/tags/creampie/"),
            Category(name: "口交", basePath: "/tags/blowjob/"),
            Category(name: "深喉", basePath: "/tags/deep-throat/"),
            Category(name: "乳交", basePath: "/tags/tit-wank/"),
            Category(name: "肛交", basePath: "/tags/anal-sex/"),
            Category(name: "潮吹", basePath: "/tags/squirting/"),
            Category(name: "顏射", basePath: "/tags/facial/"),
            Category(name: "接吻", basePath: "/tags/kiss/"),
            Category(name: "腳交", basePath: "/tags/footjob/")
        ]),
        CategoryGroup(group: "玩法", items: [
            Category(name: "多P", basePath: "/tags/groupsex/"),
            Category(name: "3P", basePath: "/tags/3p/"),
            Category(name: "痴漢", basePath: "/tags/chikan/"),
            Category(name: "露出", basePath: "/tags/outdoor/"),
            Category(name: "綑綁", basePath: "/tags/bondage/"),
            Category(name: "調教", basePath: "/tags/tune/"),
            Category(name: "凌辱", basePath: "/tags/insult/"),
            Category(name: "按摩", basePath: "/tags/massage/"),
            Category(name: "泡姬", basePath: "/tags/soapland/"),
            Category(name: "痴女", basePath: "/tags/chizyo/"),
            Category(name: "泥醉", basePath: "/tags/crapulence/"),
            Category(name: "放尿", basePath: "/tags/piss/")
        ]),
        CategoryGroup(group: "劇情", items: [
            Category(name: "NTR", basePath: "/tags/ntr/"),
            Category(name: "夫目前犯", basePath: "/tags/sex-beside-husband/"),
            Category(name: "出軌", basePath: "/tags/affair/"),
            Category(name: "偷拍", basePath: "/tags/private-cam/"),
            Category(name: "時間停止", basePath: "/tags/time-stop/"),
            Category(name: "催眠", basePath: "/tags/hypnosis/"),
            Category(name: "誘惑", basePath: "/tags/temptation/"),
            Category(name: "年齡差", basePath: "/tags/age-difference/"),
            Category(name: "童貞", basePath: "/tags/virginity/"),
            Category(name: "親屬", basePath: "/tags/kinship/"),
            Category(name: "復仇", basePath: "/tags/avenge/"),
            Category(name: "黑人", basePath: "/tags/black/")
        ]),
        CategoryGroup(group: "角色", items: [
            Category(name: "人妻", basePath: "/tags/wife/"),
            Category(name: "OL", basePath: "/tags/ol/"),
            Category(name: "護士", basePath: "/tags/nurse/"),
            Category(name: "老師", basePath: "/tags/teacher/"),
            Category(name: "醫生", basePath: "/tags/doctor/"),
            Category(name: "空姐", basePath: "/tags/flight-attendant/"),
            Category(name: "主播", basePath: "/tags/female-anchor/"),
            Category(name: "偶像", basePath: "/tags/idol/"),
            Category(name: "家政婦", basePath: "/tags/housewife/"),
            Category(name: "搜查官", basePath: "/tags/detective/"),
            Category(name: "未亡人", basePath: "/tags/widow/"),
            Category(name: "情侶", basePath: "/tags/couple/")
        ]),
        CategoryGroup(group: "地點", items: [
            Category(name: "溫泉", basePath: "/tags/hot-spring/"),
            Category(name: "健身房", basePath: "/tags/gym-room/"),
            Category(name: "學校", basePath: "/tags/school/"),
            Category(name: "電車", basePath: "/tags/tram/"),
            Category(name: "汽車", basePath: "/tags/car/"),
            Category(name: "泳池", basePath: "/tags/swimming-pool/"),
            Category(name: "魔鏡號", basePath: "/tags/magic-mirror/"),
            Category(name: "圖書館", basePath: "/tags/library/"),
            Category(name: "洗浴場", basePath: "/tags/bathing-place/"),
            Category(name: "便利店", basePath: "/tags/store/")
        ]),
        CategoryGroup(group: "雜項", items: [
            Category(name: "處女作", basePath: "/tags/debut-retires/"),
            Category(name: "感謝祭", basePath: "/tags/thanksgiving/"),
            Category(name: "綜藝", basePath: "/tags/variety-show/"),
            Category(name: "4小時以上", basePath: "/tags/more-than-4-hours/"),
            Category(name: "節日主題", basePath: "/tags/festival/")
        ])
    ]

    /// 拍平用于查找
    static let allCategories: [Category] = categoryGroups.flatMap { $0.items }

    static func url(_ path: String) -> URL {
        if path.hasPrefix("http"), let u = URL(string: path) { return u }
        if path.hasPrefix("/"), let u = URL(string: base + path) { return u }
        if let u = URL(string: base + "/" + path) { return u }
        return URL(string: base)!
    }

    static func searchPath(_ keyword: String) -> String {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? keyword
        return "/search/" + encoded + "/"
    }
}

// MARK: - 模型

struct CategoryGroup: Identifiable {
    var id: String { group }
    let group: String
    let items: [Category]
}

struct Category: Identifiable, Hashable {
    var id: String { basePath }
    let name: String
    let basePath: String

    func pagePath(_ page: Int) -> String {
        guard page > 1 else { return basePath }
        // jable 分页是路径式：/latest-updates/2/
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
        return base + "\(page)/"
    }
}

struct VideoItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let cover: String
    let duration: String
    /// 详情页路径（jable: /videos/{slug}/）
    let playPath: String

    var coverURL: URL? {
        guard !cover.isEmpty, let u = URL(string: cover) else { return nil }
        return u
    }

    var subtitle: String {
        duration.isEmpty ? "点击播放" : duration
    }

    /// 片名开头的番号，如 ABF-403 / SDJS-388
    var code: String? {
        let pattern = "^([A-Za-z]{2,6}-?[0-9]{2,5})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = title as NSString
        guard let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: match.range(at: 1)).uppercased()
    }

    /// 去掉番号后的标题，卡片上更干净
    var cleanTitle: String {
        guard let code = code, let range = title.range(of: code) else { return title }
        var rest = String(title[range.upperBound...])
        rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " -_·"))
        return rest.isEmpty ? title : rest
    }

    static func == (lhs: VideoItem, rhs: VideoItem) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PlaySource {
    let title: String
    let url: URL
}

// MARK: - 错误

enum KanError: LocalizedError {
    case badStatus(Int)
    case emptyBody
    case decodeFailed
    case noPlayURL
    case challenge

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "服务器返回 \(code)，稍后重试"
        case .emptyBody: return "返回内容为空"
        case .decodeFailed: return "网页内容解析失败"
        case .noPlayURL: return "这条暂时解析不出播放地址"
        case .challenge: return "站点人机验证未通过，请重试"
        }
    }
}
