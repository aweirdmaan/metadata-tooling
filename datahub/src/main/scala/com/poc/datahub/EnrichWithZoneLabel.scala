package com.poc.datahub

import org.apache.spark.sql.{Dataset, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types.IntegerType
import scopt.OParser

case class ZoneLookup(bucket: Int, zone_label: String)
case class EnrichedSensorProfile(sensor_id: String, avg_metric_1: Double, avg_metric_2: Double, zone_label: String)
case class EnrichWithZoneLabelArgs(
  sensorProfilesPath: String = "",
  zoneLookupPath: String = "",
  outputPath: String = "",
)

object EnrichWithZoneLabel extends SparkMain[EnrichWithZoneLabelArgs] {

  val appName = "enrich_with_zone_label"

  val defaultArgs = EnrichWithZoneLabelArgs()

  override protected def sparkBuilder() =
    DatahubSparkSession.builder(appName).appName(appName).master("local[*]")

  val argParser: OParser[Unit, EnrichWithZoneLabelArgs] = {
    val b = OParser.builder[EnrichWithZoneLabelArgs]
    import b._
    OParser.sequence(
      programName(appName),
      opt[String]("sensor-profiles-path").required().action((v, a) => a.copy(sensorProfilesPath = v)),
      opt[String]("zone-lookup-path").required().action((v, a) => a.copy(zoneLookupPath = v)),
      opt[String]("output-path").required().action((v, a) => a.copy(outputPath = v)),
    )
  }

  def run(args: EnrichWithZoneLabelArgs)(implicit spark: SparkSession): Unit = {
    import spark.implicits._
    val locations = spark.read.parquet(args.sensorProfilesPath).as[SensorProfile]
    val lookup    = DatasetIO.readCsv[ZoneLookup](args.zoneLookupPath)
    DatasetIO.writeParquet(enrich(locations, lookup), args.outputPath)
  }

  def enrich(locations: Dataset[SensorProfile], lookup: Dataset[ZoneLookup])(implicit spark: SparkSession): Dataset[EnrichedSensorProfile] = {
    import spark.implicits._
    locations
      .join(lookup, floor(col("avg_metric_1")).cast(IntegerType) === col("bucket"), "left")
      .select(
        col("sensor_id"),
        col("avg_metric_1"),
        col("avg_metric_2"),
        coalesce(col("zone_label"), lit("unknown")).as("zone_label"),
      )
      .as[EnrichedSensorProfile]
  }
}
