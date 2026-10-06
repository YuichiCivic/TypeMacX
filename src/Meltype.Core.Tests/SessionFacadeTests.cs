// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Yukishiro

using Meltype.Composition;
using Meltype.Config;
using Meltype.Input;

namespace Meltype.Tests;

/// <summary>Mac 版・Linux 版から使う入力の本体 (MeltypeSession) のテスト。OS がキーを 1 つずつ渡し、使ったかをその場で返す。</summary>
internal static class SessionFacadeTests
{
    private static MeltypeSession Create() => new(CompositionTests.Detector, new CompositionTests.FakeConverter(), new CompositionOptions(), () => new Settings());

    /// <summary>文字を 1 つずつ打つ (英字は大文字なら Shift 付き)。</summary>
    private static List<SessionResult> Type(MeltypeSession session, string text, string? before = null)
    {
        var results = new List<SessionResult>();
        foreach (var c in text)
        {
            var vk = c switch
            {
                ' ' => VirtualKeys.Space,
                '\n' => VirtualKeys.Return,
                '\b' => VirtualKeys.Back,
                ',' => VirtualKeys.OemComma,
                '.' => VirtualKeys.OemPeriod,
                '-' => VirtualKeys.OemMinus,
                _ when char.IsAsciiLetter(c) => char.ToUpperInvariant(c),
                _ => c,
            };
            char? ch = c is ' ' or '\n' or '\b' ? null : c;
            results.Add(session.HandleKey(vk, ch, char.IsAsciiLetterUpper(c), false, false, false, before));
        }
        return results;
    }

    [Test]
    public static void Romaji_ComposesAndEnterCommits()
    {
        var session = Create();
        var results = Type(session, "kyouha");
        Assert.True(results.All(r => r.Consumed), "打った英字はアプリに渡さない");
        Assert.Equal("きょうは", results[^1].View?.Text);
        var enter = Type(session, "\n")[0];
        Assert.True(enter.Consumed, "Enter は確定に使う");
        Assert.Equal("きょうは", enter.Commits.Single().Text);
        Assert.True(enter.View is null, "確定したら変換ボックスを閉じる");
    }

    [Test]
    public static void EnglishWord_SpaceCommitsWithSpace()
    {
        var session = Create();
        var results = Type(session, "google ");
        Assert.Equal("google ", results[^1].Commits.Single().Text);
    }

    [Test]
    public static void KeysOutsideComposition_GoToTheApp()
    {
        var session = Create();
        Assert.True(!session.HandleKey(VirtualKeys.Left, null, false, false, false, false).Consumed, "変換ボックスが空なら矢印はアプリへ");
        Assert.True(!session.HandleKey('C', 'c', false, false, false, true).Consumed, "Command + C はアプリの操作");
        Assert.True(!Type(session, " ")[0].Consumed, "空白はアプリへ");
        session.Direct = true;
        Assert.True(!Type(session, "a")[0].Consumed, "英数 (直接入力) ならすべてアプリへ");
    }

    [Test]
    public static void ShortcutWhileComposing_CommitsThenPassesTheKey()
    {
        var session = Create();
        Type(session, "abc");
        var result = session.HandleKey('S', 's', false, false, false, true);
        Assert.True(!result.Consumed, "Command + S はアプリへ");
        Assert.True(result.Commits.Count == 1, "その前に変換ボックスの内容を確定する");
    }

    [Test]
    public static void ArrowWhileComposing_SelectsClauses()
    {
        var session = Create();
        Type(session, "kyouha");
        var result = session.HandleKey(VirtualKeys.Right, null, false, false, false, false);
        Assert.True(result.Consumed && result.View is { Converting: true }, "変換前の矢印は文節の選択に使う");
    }

    [Test]
    public static void Candidates_CanBeSelectedByIndex()
    {
        var session = Create();
        Type(session, "api ");
        var view = session.SelectCandidate(2).View!;
        Assert.Equal(2, view.SelectedIndex);
        var commit = Type(session, "\n")[0];
        Assert.Equal(view.Candidates[2], commit.Commits.Single().Text);
    }

    [Test]
    public static void CodeApp_CodeLinePassesThrough_CommentComposes()
    {
        var session = Create();
        session.Profile = AppProfile.Code;
        Assert.True(Type(session, "kyouha", "let x = ").All(r => !r.Consumed), "コードの行では英字をそのままアプリに渡す");
        Assert.True(Type(session, "kyouha", "    // ").All(r => r.Consumed), "コメントの中では日本語を判定する");
        Type(session, "\n");
        Assert.True(Type(session, "kyouha", "> ").All(r => r.Consumed), "AI の入力行 (「> 」の後) では日本語を判定する");
        Type(session, "\n");
        Assert.True(!Type(session, "a")[0].Consumed, "キャレットの前が分からなければコードとみなす");
        // 長い before でも、行頭のコメントの記号で判定する (変換ボックスには後ろだけを渡す)。
        Assert.True(Type(session, "k", "// " + new string('a', 100) + " ")[0].Consumed, "長い行のコメント");
        Type(session, "\n");
    }

    [Test]
    public static void CodeApp_CodeJapaneseUntilEnter()
    {
        var session = Create();
        session.Profile = AppProfile.Code;
        session.CodeJapanese = true;
        Assert.True(Type(session, "kyouha", "let x = ").All(r => r.Consumed), "「かな」を押した行はコードでも日本語");
        Type(session, "\n");
        Assert.True(Type(session, "\n")[0] is { Consumed: false }, "変換ボックスが空の Enter はアプリへ");
        Assert.True(!session.CodeJapanese, "改行でコードに戻る");
        Assert.True(!Type(session, "a", "let x = ")[0].Consumed, "次の行はコードの行として英数");
    }

    [Test]
    public static void DisabledApp_PassesEverything()
    {
        var session = Create();
        session.Profile = AppProfile.Game;
        Assert.True(Type(session, "kyouha").All(r => !r.Consumed), "無効のアプリではキーをすべてアプリに渡す");
    }

    [Test]
    public static void Json_IsEscaped()
    {
        var result = new SessionResult(true, [new TextEdit(2, "a\"b\\c\n")], new CompositionView("x", ["y"], 0, true, "h", ["x"], 0));
        const string expected = """{"consumed":true,"commits":[{"deleteBefore":2,"text":"a\"b\\c\n"}],"view":{"text":"x","converting":true,"selectedIndex":0,"selectedClause":0,"hint":"h","candidates":["y"],"clauses":["x"],"suggestion":null,"meaning":null}}""";
        Assert.Equal(expected, result.ToJson());
    }
}
