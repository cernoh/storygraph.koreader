require("spec_helper")

describe("Main plugin helpers", function()
    -- Extract and test pure logic from main.lua without loading it
    -- (main.lua extends WidgetContainer and needs full KOReader env)

    -- getBookId logic: ISBN takes priority, else title+author hash
    local function getBookId(props)
        if props.isbn and props.isbn ~= "" then
            return "isbn:" .. props.isbn
        end
        local key = (props.title or "") .. (props.authors or "")
        if key ~= "" then
            local hash = 0
            for i = 1, #key do
                hash = (hash * 31 + string.byte(key, i)) % 2^32
            end
            return "hash:" .. string.format("%08x", hash)
        end
        return nil
    end

    -- getReadingPercentage logic
    local function getReadingPercentage(current_page, total_pages)
        if total_pages and total_pages > 0 then
            return math.floor((current_page / total_pages) * 100)
        end
        return 0
    end

    describe("getBookId", function()
        it("returns isbn: prefix when ISBN present", function()
            local id = getBookId({ isbn = "978-3-16-148410-0" })
            assert.are.equal("isbn:978-3-16-148410-0", id)
        end)

        it("prefers ISBN over title+author", function()
            local id = getBookId({
                isbn = "978-3-16-148410-0",
                title = "Some Book",
                authors = "Some Author",
            })
            assert.are.equal("isbn:978-3-16-148410-0", id)
        end)

        it("returns hash: prefix when no ISBN but title+author present", function()
            local id = getBookId({ title = "Test Book", authors = "Test Author" })
            assert.truthy(id:match("^hash:"))
        end)

        it("produces consistent hash for same title+author", function()
            local id1 = getBookId({ title = "Dune", authors = "Frank Herbert" })
            local id2 = getBookId({ title = "Dune", authors = "Frank Herbert" })
            assert.are.equal(id1, id2)
        end)

        it("produces different hashes for different books", function()
            local id1 = getBookId({ title = "Dune", authors = "Frank Herbert" })
            local id2 = getBookId({ title = "Foundation", authors = "Isaac Asimov" })
            assert.are_not.equal(id1, id2)
        end)

        it("returns nil when no identifying info", function()
            local id = getBookId({})
            assert.is_nil(id)
        end)

        it("returns nil when ISBN is empty string and no title/authors", function()
            local id = getBookId({ isbn = "", title = "", authors = "" })
            assert.is_nil(id)
        end)

        it("handles title without authors", function()
            local id = getBookId({ title = "Anonymous Work" })
            assert.truthy(id:match("^hash:"))
        end)

        it("handles authors without title", function()
            local id = getBookId({ authors = "Unknown Author" })
            assert.truthy(id:match("^hash:"))
        end)

        it("hash is 8 hex characters", function()
            local id = getBookId({ title = "Test", authors = "Author" })
            local hex = id:match("^hash:([0-9a-f]+)$")
            assert.is_not_nil(hex)
            assert.are.equal(8, #hex)
        end)
    end)

    describe("getReadingPercentage", function()
        it("returns correct percentage for midpoint", function()
            assert.are.equal(50, getReadingPercentage(150, 300))
        end)

        it("returns 0 for first page of many", function()
            assert.are.equal(0, getReadingPercentage(0, 300))
        end)

        it("returns 100 for last page", function()
            assert.are.equal(100, getReadingPercentage(300, 300))
        end)

        it("floors fractional percentages", function()
            assert.are.equal(33, getReadingPercentage(1, 3))
        end)

        it("returns 0 when total_pages is 0", function()
            assert.are.equal(0, getReadingPercentage(50, 0))
        end)

        it("returns 0 when total_pages is nil", function()
            assert.are.equal(0, getReadingPercentage(50, nil))
        end)

        it("handles large page counts", function()
            assert.are.equal(50, getReadingPercentage(500, 1000))
        end)

        it("handles single page book", function()
            assert.are.equal(100, getReadingPercentage(1, 1))
        end)
    end)
end)
