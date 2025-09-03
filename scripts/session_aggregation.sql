WITH sessions_2023 AS (
    SELECT *
    FROM sessions s
    WHERE s.session_start > '2023-01-04'
),
cohort AS (
    SELECT user_id, COUNT(*) AS session_count
    FROM sessions_2023
    GROUP BY user_id
    HAVING COUNT(*) > 7
),
home_airports AS (
    SELECT DISTINCT home_airport, home_airport_lat, home_airport_lon
    FROM users
),
cancelled_trips AS (
		SELECT DISTINCT trip_id
  	FROM sessions
  	WHERE cancellation = true
),
session_aggregate_stage1 AS (
    SELECT
        s.session_id,
        s.user_id,
        s.trip_id,
        s.session_start,
        s.session_end,
        s.flight_discount,
        s.hotel_discount,
        s.flight_discount_amount,
        s.hotel_discount_amount,
        s.flight_booked,
        s.hotel_booked,
        s.page_clicks,
        s.cancellation,
        EXTRACT(EPOCH FROM (s.session_end - s.session_start)) AS session_duration_in_seconds,
        CASE WHEN ((flight_booked OR hotel_booked) AND NOT cancellation) THEN session_start END AS booking_session_date,
        CASE WHEN cancellation THEN session_start END AS cancellation_session_date,
        CASE
            WHEN (flight_booked OR hotel_booked) THEN
                CASE WHEN COALESCE(departure_time, '3000-01-01') < COALESCE(check_in_time, '3000-01-01')
                     THEN COALESCE(departure_time, '3000-01-01')
                     ELSE COALESCE(check_in_time, '3000-01-01')
                END
        END AS trip_start_date,
  			CASE WHEN ct.trip_id is not null THEN TRUE
  					 WHEN s.trip_id is null THEN null
						 ELSE FALSE
  			END AS trip_is_cancelled,
        u.birthdate,
        EXTRACT(YEAR FROM AGE('2023-07-28', u.birthdate)) AS age_in_years,
        u.gender,
        u.married,
        u.has_children,
        u.home_country,
        u.home_city,
        u.home_airport,
        u.home_airport_lat,
        u.home_airport_lon,
        u.sign_up_date,
        ('2023-07-28'::date - u.sign_up_date::date) AS days_as_customer,
        h.hotel_name,
        TRIM(SPLIT_PART(h.hotel_name, ' - ', 1)) AS hotel_chain,
        TRIM(SPLIT_PART(h.hotel_name, ' - ', 2)) AS hotel_location,
        (h.check_out_time::date - h.check_in_time::date) AS stay_in_nights,
        h.rooms,
        h.nights,
        h.check_in_time,
        h.check_out_time,
        h.hotel_per_room_usd,
        s.hotel_discount_amount * h.hotel_per_room_usd AS hotel_per_room_savings_usd,
        f.origin_airport,
        ha.home_airport_lat AS origin_airport_lat,
        ha.home_airport_lon AS origin_airport_lon,
        f.destination_airport,
        f.destination,
        f.seats,
        f.return_flight_booked,
        f.departure_time,
        f.return_time,
        f.checked_bags,
        f.trip_airline,
        f.destination_airport_lat,
        f.destination_airport_lon,
        f.base_fare_usd,
        s.flight_discount_amount * f.base_fare_usd AS flight_fare_savings_usd
    FROM sessions s
    JOIN users u ON s.user_id = u.user_id
    LEFT JOIN flights f ON s.trip_id = f.trip_id
    LEFT JOIN hotels h ON s.trip_id = h.trip_id
    LEFT JOIN home_airports ha ON f.origin_airport = ha.home_airport
  	LEFT JOIN cancelled_trips ct ON s.trip_id = ct.trip_id
    WHERE s.user_id IN (SELECT user_id FROM cohort)
      AND s.session_start >= '2023-01-04'
),
session_aggregate_stage2 AS (
    SELECT *,
        CASE WHEN booking_session_date IS NOT NULL AND trip_start_date IS NOT NULL
             THEN trip_start_date::date - booking_session_date::date END AS booking_lead_time_in_days,
        CASE WHEN cancellation_session_date IS NOT NULL AND trip_start_date IS NOT NULL
             THEN trip_start_date::date - cancellation_session_date::date END AS cancellation_lead_time_in_days,
        6371 * 2 * ASIN(
            SQRT(
                POWER(SIN(RADIANS(destination_airport_lat - origin_airport_lat) / 2), 2) +
                COS(RADIANS(origin_airport_lat)) *
                COS(RADIANS(destination_airport_lat)) *
                POWER(SIN(RADIANS(destination_airport_lon - origin_airport_lon) / 2), 2)
            )
        ) AS distance_flown_km
    FROM session_aggregate_stage1
),
session_aggregate AS (
    SELECT *,
        CASE WHEN distance_flown_km >= 4800 THEN true
             WHEN distance_flown_km IS NULL THEN NULL
             ELSE false
        END AS is_longhaul_flight
    FROM session_aggregate_stage2
)
select * from session_aggregate;