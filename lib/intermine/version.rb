module Intermine

    # Webservice Client Version number
    #
    # Changes:
    #   1.02.00 - Allow the lazy fetching to be optional
    #   1.01.01 - Improved lazy reference fetching
    #   1.01.00 - Test compatibility with 1.8.7, 1.9.2, 2.0.0-rc1
    #             Numerous bug fixes.
    #   1.00.00 - Up to make use of new features of the InterMine 1.0 API
    #             * Enrichment queries
    #             * Range constraints
    #   0.98.11 - * InterMineObjects now lazily fetch their references 
    #             if nil. Note that while extremely convenient, 
    #             explicit prefetching will be much more efficient 
    #             (how much depends on the number of extra requests, but
    #             a factor of 10 seems pretty common).
    #             * Added support for list tagging
    #   0.98.10 - Added status property to lists
    #   0.98.09 - Major changes to results - now with thorough-going Enumerable support
    #   0.98.08 - Added column summary support
    #
    VERSION = "1.01.01"
end
