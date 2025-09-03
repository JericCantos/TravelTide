# TravelTide
Customer Segmentation for a Travel e-Booking Site.

This project contains the entire project lifecycle, starting from EDA, data cleaning, attempts at clustering through machine learning and traditional segmentation, as well as final recommendations regarding strategies for engaging the resulting segments through potential fitting perks.

## notebooks

Though I have exported the various dataframes as CSV files, none of them would be needed to run these notebooks as they are pulling the data directly from the original database source through SQL scripts. Simply save a copy and run them, no particular setup necessary.

- TravelTide_EDA: Begin here to have a broad look at the data, starting from the raw tables, to the session-level aggregation, and finally to the user-level aggregation.
- TravelTide_Clustering_Initial: Shows the initial attempt at using machine learning for segmentation, and why it was not satisfactory.
- TravelTide_Clustering_Hybrid: A combination of traditional and machine learning segmentation that is more useful for the business at targeting users.
- TravelTide: original big notebook just kept for posterity and reference.

## reports
Cotains the synthesis of the segmentation and the resulting strategies in a presentation.

## data
To connect to the database containing the Travel Tide data, refer to the connection string under `data/raw`.

We are given transactional data across four tables:
1. users: contains user demographic information (e.g. birthdate, gender, marital status)
2. sessions: main transaction table containing infoormation on user activities (e.g. did they book? how many clicks? how long?)
3. flights: contains info about purchased flights (e.g. origin and destination, checked bags, base fare)
4. hotels: contains info about booked hotels (e.g. hotel chain and location, check-in and check-out time, room rate)

I have exported the raw session-level aggregation as well as the cleaned user-level aggregation as csv files. They can be found under `data/processed`

## outputs
 The users of each traditionally-defined persona have been isolated and their details extracted in separate csv files.

 The users who were not addressed by these personas were clustered using KMeans, and the entire dataset with groupings have been exported to its own file (`df_unaddressed_users_clustered.csv`)

## scripts
Contains the SQL scripts used for extracting the session-level and user-level aggregations, as well as calculating average churn. These were factored out as their own SQL scripts for better readability of the notebooks overall.