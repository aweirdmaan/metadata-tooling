package com.poc.datahub

import org.apache.spark.sql.{Dataset, SparkSession}
import org.apache.spark.sql.functions._
import scopt.OParser

case class Reading(sensor_id: String, metric_1: Double, metric_2: Double, ts: String)
case class SensorProfile(sensor_id: String, avg_metric_1: Double, avg_metric_2: Double, confidence: Double)
case class BuildSensorProfilesArgs(inputPath: String = "", outputPath: String = "")

object BuildSensorProfiles extends SparkMain[BuildSensorProfilesArgs] {

  val appName = "build_sensor_profiles"

  val defaultArgs = BuildSensorProfilesArgs()

  override protected def sparkBuilder() =
    DatahubSparkSession.builder(appName).appName(appName).master("local[*]")

  val argParser: OParser[Unit, BuildSensorProfilesArgs] = {
    val b = OParser.builder[BuildSensorProfilesArgs]
    import b._
    OParser.sequence(
      programName(appName),
      opt[String]("input-path").required().action((v, a) => a.copy(inputPath = v)),
      opt[String]("output-path").required().action((v, a) => a.copy(outputPath = v)),
    )
  }

  def run(args: BuildSensorProfilesArgs)(implicit spark: SparkSession): Unit = {
    import spark.implicits._
    val locations = aggregate(DatasetIO.readCsv[Reading](args.inputPath))
    DatasetIO.writeParquet(locations, args.outputPath)
  }

  def aggregate(sensor_readings: Dataset[Reading])(implicit spark: SparkSession): Dataset[SensorProfile] = {
    import spark.implicits._
    sensor_readings
      .filter(col("sensor_id").isNotNull && col("sensor_id") =!= "")
      .groupBy("sensor_id")
      .agg(
        avg("metric_1").as("avg_metric_1"),
        avg("metric_2").as("avg_metric_2"),
        (count("*") / lit(100.0)).as("confidence"),
      )
      .as[SensorProfile]
  }
}
