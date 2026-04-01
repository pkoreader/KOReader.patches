# KOReader.patches

2-star-rating-hardcover.lua
I took idea from https://github.com/ImSoRight/KOReader.patches#2-star-rating-overlay.
It takes your hardcover linked book’s ratings and use it to show the star overlay on the respective books.  
When books are not linked, it checks metadata of the book and display those ratings onto the cover. 
If both hardcover and metadata have the ratings, then it gives priority to hardcover ratings as their ratings have the facility of a half star. 
Note: 
The ratings are stored under koreader/cache/2StarRatingHardcover.json which is created automatically.
In order to display hardcover ratings, you need to have hardcover plugin installed and need to have your books linked.

PS. This patch was created using AI and i have tested it on android and kindle PW 12. 

![Screenshot_20260310_223641](https://github.com/user-attachments/assets/074f2e63-76aa-46d0-9301-a27aeb31ebe4)


